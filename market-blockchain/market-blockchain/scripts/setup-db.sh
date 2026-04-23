#!/bin/bash
# Database initialization script for development

set -e

echo "=== Market Blockchain Database Setup ==="

# Check if PostgreSQL is running
if ! command -v psql &> /dev/null; then
    echo "Error: PostgreSQL is not installed or not in PATH"
    exit 1
fi

# Default values
DB_NAME="market_blockchain"
DB_USER="postgres"
DB_HOST="localhost"
DB_PORT="5432"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --db-name)
            DB_NAME="$2"
            shift 2
            ;;
        --db-user)
            DB_USER="$2"
            shift 2
            ;;
        --db-host)
            DB_HOST="$2"
            shift 2
            ;;
        --db-port)
            DB_PORT="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--db-name NAME] [--db-user USER] [--db-host HOST] [--db-port PORT]"
            exit 1
            ;;
    esac
done

echo "Database: $DB_NAME"
echo "User: $DB_USER"
echo "Host: $DB_HOST"
echo "Port: $DB_PORT"
echo ""

# Create database if it doesn't exist
echo "1. Creating database..."
psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -tc "SELECT 1 FROM pg_database WHERE datname = '$DB_NAME'" | grep -q 1 || \
    psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -c "CREATE DATABASE $DB_NAME"
echo "✓ Database ready"

# Run migrations
echo ""
echo "2. Running migrations..."
MIGRATION_DIR="$(dirname "$0")/../internal/store/migrations"

for migration in "$MIGRATION_DIR"/*.sql; do
    if [ -f "$migration" ]; then
        echo "   Applying $(basename "$migration")..."
        psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -f "$migration"
    fi
done
echo "✓ Migrations completed"

# Insert sample plans
echo ""
echo "3. Inserting sample plans..."
psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" <<EOF
INSERT INTO plans (plan_id, name, description, period_seconds, amount_usdc_base_units, amount_usdc_display, authorization_periods, total_authorization_amount, active, created_at, updated_at)
VALUES
    ('plan_basic_monthly', 'Basic Monthly', 'Basic plan with 30-day billing cycle', 2592000, 1000000, '1.00 USDC', 3, 3000000, true, extract(epoch from now()) * 1000, extract(epoch from now()) * 1000),
    ('plan_premium_monthly', 'Premium Monthly', 'Premium plan with 30-day billing cycle', 2592000, 5000000, '5.00 USDC', 3, 15000000, true, extract(epoch from now()) * 1000, extract(epoch from now()) * 1000),
    ('plan_enterprise_monthly', 'Enterprise Monthly', 'Enterprise plan with 30-day billing cycle', 2592000, 10000000, '10.00 USDC', 3, 30000000, true, extract(epoch from now()) * 1000, extract(epoch from now()) * 1000)
ON CONFLICT (plan_id) DO NOTHING;
EOF
echo "✓ Sample plans inserted"

echo ""
echo "=== Setup Complete ==="
echo ""
echo "Database URL:"
echo "postgres://$DB_USER@$DB_HOST:$DB_PORT/$DB_NAME?sslmode=disable"
echo ""
echo "Update your .env file with:"
echo "DATABASE_URL=postgres://$DB_USER@$DB_HOST:$DB_PORT/$DB_NAME?sslmode=disable"
