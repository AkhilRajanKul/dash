#!/bin/ash

set -e  # Exit on any error

echo "Apply database migrations"
python manage.py migrate

exec "$@"