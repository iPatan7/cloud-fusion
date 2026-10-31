#!/bin/sh
# Moves the CivicSense application into a Cloud Fusion VM: the code is taken from
# the civicsense-devops repository (git archive of main), installed in a Python
# virtual environment with SQLite, and run by gunicorn as a systemd service on
# port 8000. The same steps would run unchanged on VMware or on an EC2 instance.
#
#   app/deploy-civicsense.sh <vm> [repository]
set -eu
VM=$1
REPO=${2:-"$(cd "$(dirname "$0")/../../../.." && pwd)/DEVOPS PROCESS AUTOMATION LAB/project/civicsense-devops"}
HERE=$(cd "$(dirname "$0")/.." && pwd)
ssh_vm() { "$HERE/kvm/ssh.sh" "$VM" "$@"; }
now() { date +%s.%N; }
since() { awk -v a="$1" -v b="$(now)" 'BEGIN { printf "%.1f", b - a }'; }

t=$(now)
git -C "$REPO" archive --format=tar main -- accounts civicsense complaints dashboard nlpengine \
    static templates manage.py | ssh_vm 'sudo mkdir -p /opt/civicsense && sudo tar -x -C /opt/civicsense && sudo chown -R civic: /opt/civicsense'
echo "code copied in $(since "$t") s ($(git -C "$REPO" rev-parse --short main))"

t=$(now)
ssh_vm 'set -e
cd /opt/civicsense
python3 -m venv /opt/civicsense/venv
/opt/civicsense/venv/bin/pip install -q --disable-pip-version-check "Django>=5.2" gunicorn whitenoise python-dotenv
umask 077
printf "DJANGO_SECRET_KEY=%s\nDJANGO_DEBUG=0\nDJANGO_ALLOWED_HOSTS=*\nCIVIC_RELEASE=%s\nCIVIC_SLOT=kvm\n" \
  "$(head -c 32 /dev/urandom | od -An -tx1 | tr -d " \n")" "'"$(git -C "$REPO" rev-parse --short=8 main)"'" > /opt/civicsense/.env
/opt/civicsense/venv/bin/python manage.py migrate --no-input >/dev/null
/opt/civicsense/venv/bin/python manage.py collectstatic --no-input >/dev/null
/opt/civicsense/venv/bin/python manage.py seed_demo >/dev/null'
echo "virtual environment, database and demo data in $(since "$t") s"

ssh_vm 'sudo tee /etc/systemd/system/civicsense.service >/dev/null <<EOF
[Unit]
Description=CivicSense (gunicorn)
After=network-online.target
[Service]
User=civic
WorkingDirectory=/opt/civicsense
ExecStart=/opt/civicsense/venv/bin/gunicorn civicsense.wsgi:application --bind 0.0.0.0:8000 --workers 2 --access-logfile -
Restart=on-failure
[Install]
WantedBy=multi-user.target
EOF
sudo systemctl daemon-reload && sudo systemctl enable --now civicsense >/dev/null 2>&1'
t=$(now)
until ssh_vm 'curl -fs -o /dev/null http://localhost:8000/healthz' 2>/dev/null; do sleep 0.5; done
echo "gunicorn answering after $(since "$t") s: $(ssh_vm 'curl -s http://localhost:8000/healthz')"
