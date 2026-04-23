# Admin Interface Quick Start

## Overview

The admin interface provides a web-based dashboard for monitoring and managing the Market Blockchain subscription service.

## Features

- **Dashboard**: View key metrics (active subscriptions, revenue, pending/failed charges)
- **Plans Management**: View all subscription plans with active subscriber counts
- **Subscriptions**: List and filter subscriptions by status
- **Real-time Events**: Monitor recent system events

## Access

Once the server is running, access the admin interface at:

```
http://localhost:8080/admin/
```

## API Endpoints

### Dashboard
- `GET /admin/api/v1/dashboard/metrics` - Get overview metrics
- `GET /admin/api/v1/dashboard/revenue-trend` - Get revenue trend data
- `GET /admin/api/v1/dashboard/subscription-distribution` - Get subscription status distribution
- `GET /admin/api/v1/dashboard/recent-events` - Get recent system events

### Plans
- `GET /admin/api/v1/plans` - List all plans with subscriber counts
- `POST /admin/api/v1/plans` - Create new plan
- `PUT /admin/api/v1/plans/{id}` - Update plan

### Subscriptions
- `GET /admin/api/v1/subscriptions` - List subscriptions (supports filtering and pagination)

## Design System

The admin interface follows the **Dark Mode (OLED)** design system:
- **Primary Color**: #1E40AF (Blue) - for data and primary actions
- **CTA/Accent**: #F59E0B (Amber) - for highlights and important actions
- **Background**: #0F172A (Deep black) - OLED-optimized
- **Typography**: Fira Code (headings/data), Fira Sans (body text)

## Implementation Status

**Phase 1: Backend API** ✅ Complete
- Dashboard metrics aggregation
- Plan management endpoints
- Subscription listing with pagination
- Event tracking

**Phase 2: Frontend** ✅ Complete
- Responsive dashboard layout
- Real-time metrics display
- Plan listing with stats
- Subscription table with filtering

**Phase 3: Advanced Features** 🚧 Planned
- Charge monitoring with date ranges
- Authorization tracking
- Detailed event logs
- Export functionality

## Next Steps

1. Start the server: `./bin/server`
2. Open browser to `http://localhost:8080/admin/`
3. View dashboard metrics and explore plans/subscriptions

For detailed API documentation, see [API.md](API.md).
