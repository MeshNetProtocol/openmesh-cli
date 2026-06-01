# Admin Interface Design Document

**Project:** Market Blockchain Admin Dashboard  
**Version:** V1  
**Created:** 2026-04-23  
**Purpose:** Comprehensive admin interface for subscription management system monitoring and control

---

## 1. Overview

### 1.1 Purpose

The admin interface provides administrators with comprehensive tools to:
- Monitor subscription lifecycle and health
- Manage subscription plans and pricing
- Track charges and payment processing
- Review authorization status and allowances
- Analyze system events and audit trails
- View analytics and key metrics

### 1.2 Design System

This interface follows the **Dark Mode (OLED)** design system with:
- **Primary Color:** #1E40AF (Blue) - for data and primary actions
- **CTA/Accent:** #F59E0B (Amber) - for highlights and important actions
- **Background:** #0F172A (Deep black) - OLED-optimized
- **Typography:** Fira Code (headings/data), Fira Sans (body text)
- **Style:** Technical dashboard optimized for data density and readability

---

## 2. Architecture

### 2.1 System Architecture

```
┌─────────────────────────────────────────────────────────┐
│                   Admin Frontend                         │
│              (HTML + Tailwind CSS + Alpine.js)          │
└────────────────────┬────────────────────────────────────┘
                     │ HTTP/REST
┌────────────────────▼────────────────────────────────────┐
│              Admin API Layer (Go)                        │
│  ┌──────────────────────────────────────────────────┐  │
│  │  GET  /admin/dashboard                           │  │
│  │  GET  /admin/plans                               │  │
│  │  POST /admin/plans                               │  │
│  │  GET  /admin/subscriptions                       │  │
│  │  GET  /admin/charges                             │  │
│  │  GET  /admin/authorizations                      │  │
│  │  GET  /admin/events                              │  │
│  │  GET  /admin/analytics                           │  │
│  └──────────────────────────────────────────────────┘  │
└────────────────────┬────────────────────────────────────┘
                     │
┌────────────────────▼────────────────────────────────────┐
│           Existing Service Layer                         │
│  (SubscriptionService, PlanRepository, etc.)            │
└────────────────────┬────────────────────────────────────┘
                     │
┌────────────────────▼────────────────────────────────────┐
│              PostgreSQL Database                         │
└─────────────────────────────────────────────────────────┘
```

### 2.2 Technology Stack

**Frontend:**
- HTML5 + Tailwind CSS (utility-first styling)
- Alpine.js (lightweight reactivity)
- Chart.js (data visualization)
- Heroicons (SVG icon set)

**Backend:**
- Go 1.24 (existing service extended with admin endpoints)
- Standard library HTTP handlers
- Existing repository layer (no new dependencies)

**Database:**
- PostgreSQL 12+ (existing schema)
- Read-only queries for most operations
- Write operations only for plan management

---

## 3. Page Layouts

### 3.1 Navigation Structure

```
┌─────────────────────────────────────────────────────────┐
│  [Logo] Market Blockchain Admin                         │
│  ┌──────┬──────────┬──────────┬──────────┬─────────┐  │
│  │ Home │ Plans    │ Subs     │ Charges  │ Events  │  │
│  └──────┴──────────┴──────────┴──────────┴─────────┘  │
└─────────────────────────────────────────────────────────┘
```

**Navigation Items:**
1. Dashboard (Home) - Overview metrics
2. Plans - Subscription plan management
3. Subscriptions - Active/cancelled subscription monitoring
4. Charges - Payment processing status
5. Events - System audit log

### 3.2 Dashboard Layout (Home)

```
┌─────────────────────────────────────────────────────────┐
│  Dashboard Overview                                      │
├─────────────────────────────────────────────────────────┤
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐  │
│  │ Active   │ │ Revenue  │ │ Pending  │ │ Failed   │  │
│  │ Subs     │ │ (30d)    │ │ Charges  │ │ Charges  │  │
│  │ 1,234    │ │ $12,345  │ │ 23       │ │ 5        │  │
│  └──────────┘ └──────────┘ └──────────┘ └──────────┘  │
├─────────────────────────────────────────────────────────┤
│  Revenue Trend (Last 30 Days)                           │
│  [Line Chart: Daily Revenue]                            │
├─────────────────────────────────────────────────────────┤
│  Subscription Status Distribution                       │
│  [Pie Chart: Active/Cancelled/Expired]                  │
├─────────────────────────────────────────────────────────┤
│  Recent Events (Last 10)                                │
│  [Table: Timestamp | Type | Subscription | Status]      │
└─────────────────────────────────────────────────────────┘
```

### 3.3 Plans Management Layout

```
┌─────────────────────────────────────────────────────────┐
│  Subscription Plans                    [+ New Plan]     │
├─────────────────────────────────────────────────────────┤
│  ┌─────────────────────────────────────────────────┐   │
│  │ Basic Monthly                          [Edit]   │   │
│  │ $1.00 USDC / 30 days                            │   │
│  │ Active subscribers: 456                         │   │
│  │ Authorization: 3 periods ($3.00 total)          │   │
│  └─────────────────────────────────────────────────┘   │
│  ┌─────────────────────────────────────────────────┐   │
│  │ Premium Monthly                        [Edit]   │   │
│  │ $5.00 USDC / 30 days                            │   │
│  │ Active subscribers: 234                         │   │
│  │ Authorization: 3 periods ($15.00 total)         │   │
│  └─────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────┘
```

### 3.4 Subscriptions Monitoring Layout

```
┌─────────────────────────────────────────────────────────┐
│  Subscriptions                                           │
│  [Filter: All | Active | Cancelled | Expired]           │
│  [Search: Identity Address or Payer Address]            │
├─────────────────────────────────────────────────────────┤
│  ID          │ Identity    │ Plan    │ Status  │ Period │
│  sub_123...  │ 0x1234...   │ Basic   │ Active  │ 15d    │
│  sub_456...  │ 0x5678...   │ Premium │ Active  │ 3d     │
│  sub_789...  │ 0x9abc...   │ Basic   │ Expired │ -2d    │
├─────────────────────────────────────────────────────────┤
│  [Pagination: < 1 2 3 ... 10 >]                         │
└─────────────────────────────────────────────────────────┘
```

### 3.5 Charges Monitoring Layout

```
┌─────────────────────────────────────────────────────────┐
│  Charges                                                 │
│  [Filter: All | Pending | Completed | Failed]           │
│  [Date Range: Last 7 days ▼]                            │
├─────────────────────────────────────────────────────────┤
│  ID       │ Sub ID    │ Amount  │ Status    │ Timestamp │
│  chg_123  │ sub_123   │ $1.00   │ Completed │ 2h ago    │
│  chg_456  │ sub_456   │ $5.00   │ Pending   │ 5m ago    │
│  chg_789  │ sub_789   │ $1.00   │ Failed    │ 1d ago    │
├─────────────────────────────────────────────────────────┤
│  [Pagination: < 1 2 3 ... 10 >]                         │
└─────────────────────────────────────────────────────────┘
```

### 3.6 Events Audit Log Layout

```
┌─────────────────────────────────────────────────────────┐
│  System Events                                           │
│  [Filter: All | Subscription | Charge | Authorization]  │
│  [Date Range: Last 24 hours ▼]                          │
├─────────────────────────────────────────────────────────┤
│  Timestamp        │ Type              │ Details          │
│  2026-04-23 20:15 │ subscription.created │ sub_123...   │
│  2026-04-23 20:10 │ charge.completed     │ chg_456...   │
│  2026-04-23 20:05 │ authorization.permit │ auth_789...  │
├─────────────────────────────────────────────────────────┤
│  [Pagination: < 1 2 3 ... 10 >]                         │
└─────────────────────────────────────────────────────────┘
```

---

## 4. Feature Specifications

### 4.1 Dashboard Analytics

**Metrics Cards:**
- Active Subscriptions (count)
- Total Revenue (30-day rolling)
- Pending Charges (count + total amount)
- Failed Charges (count + total amount)

**Charts:**
- Revenue Trend: Line chart showing daily revenue over 30 days
- Subscription Distribution: Pie chart showing active/cancelled/expired breakdown
- Plan Popularity: Bar chart showing subscriber count per plan

**Recent Activity:**
- Last 10 system events with timestamp, type, and status

### 4.2 Plan Management

**List View:**
- Display all plans (active and inactive)
- Show: plan_id, name, price, period, active subscriber count
- Actions: Edit, Activate/Deactivate

**Create/Edit Form:**
- Plan ID (immutable after creation)
- Name (text input)
- Description (textarea)
- Period (seconds, with helper for days/months)
- Amount (USDC base units, with display conversion)
- Authorization Periods (number)
- Active Status (toggle)

**Validation:**
- Plan ID must be unique
- Amount must be positive
- Period must be > 0
- Authorization periods must be >= 1

### 4.3 Subscription Monitoring

**List View:**
- Filterable by status (all/active/cancelled/expired)
- Searchable by identity_address or payer_address
- Display: ID, identity, payer, plan, status, period remaining
- Click row to view details

**Detail View:**
- Full subscription information
- Current period start/end timestamps
- Auto-renew status
- Pending plan change (if any)
- Associated authorization details
- Charge history for this subscription
- Event timeline

### 4.4 Charge Monitoring

**List View:**
- Filterable by status (all/pending/completed/failed)
- Date range selector
- Display: charge_id, subscription_id, amount, status, timestamp
- Click row to view details

**Detail View:**
- Full charge information
- Associated subscription
- Transaction hash (if completed)
- Error message (if failed)
- Retry attempts
- Timeline of status changes

### 4.5 Authorization Tracking

**List View:**
- Display all authorizations
- Show: identity, payer, plan, permit status, remaining allowance
- Filter by permit status

**Detail View:**
- Full authorization information
- Permit signature details (v, r, s)
- Total authorized amount
- Amount used (sum of completed charges)
- Remaining allowance
- Associated subscription

### 4.6 Event Audit Log

**List View:**
- Filterable by event type
- Date range selector
- Display: timestamp, event_type, related entity, details
- Real-time updates (polling every 30s)

**Detail View:**
- Full event payload (JSON)
- Related entities (subscription, charge, authorization)
- User/system that triggered event

---

## 5. API Endpoints

### 5.1 Dashboard Endpoints

```
GET /admin/api/v1/dashboard/metrics
Response: {
  "active_subscriptions": 1234,
  "revenue_30d": 12345.67,
  "pending_charges_count": 23,
  "pending_charges_amount": 45.00,
  "failed_charges_count": 5,
  "failed_charges_amount": 10.00
}

GET /admin/api/v1/dashboard/revenue-trend?days=30
Response: {
  "data": [
    {"date": "2026-03-24", "revenue": 123.45},
    {"date": "2026-03-25", "revenue": 234.56}
  ]
}

GET /admin/api/v1/dashboard/subscription-distribution
Response: {
  "active": 1234,
  "cancelled": 56,
  "expired": 23
}

GET /admin/api/v1/dashboard/recent-events?limit=10
Response: {
  "events": [...]
}
```

### 5.2 Plan Management Endpoints

```
GET /admin/api/v1/plans
Response: {
  "plans": [...]
}

POST /admin/api/v1/plans
Request: {
  "plan_id": "plan_custom_monthly",
  "name": "Custom Monthly",
  "description": "Custom plan",
  "period_seconds": 2592000,
  "amount_usdc_base_units": 2000000,
  "authorization_periods": 3,
  "active": true
}

PUT /admin/api/v1/plans/{plan_id}
Request: {
  "name": "Updated Name",
  "active": false
}
```

### 5.3 Subscription Monitoring Endpoints

```
GET /admin/api/v1/subscriptions?status=active&page=1&limit=50
Response: {
  "subscriptions": [...],
  "total": 1234,
  "page": 1,
  "limit": 50
}

GET /admin/api/v1/subscriptions/{id}
Response: {
  "subscription": {...},
  "authorization": {...},
  "charges": [...],
  "events": [...]
}

GET /admin/api/v1/subscriptions/search?q=0x1234
Response: {
  "subscriptions": [...]
}
```

### 5.4 Charge Monitoring Endpoints

```
GET /admin/api/v1/charges?status=pending&from=2026-04-20&to=2026-04-23
Response: {
  "charges": [...],
  "total": 23
}

GET /admin/api/v1/charges/{id}
Response: {
  "charge": {...},
  "subscription": {...}
}
```

### 5.5 Authorization Endpoints

```
GET /admin/api/v1/authorizations?permit_status=approved
Response: {
  "authorizations": [...]
}

GET /admin/api/v1/authorizations/{id}
Response: {
  "authorization": {...},
  "remaining_allowance": 2000000,
  "used_amount": 1000000
}
```

### 5.6 Event Endpoints

```
GET /admin/api/v1/events?type=subscription.created&from=2026-04-23T00:00:00Z
Response: {
  "events": [...],
  "total": 45
}

GET /admin/api/v1/events/{id}
Response: {
  "event": {...}
}
```

---

## 6. UI/UX Specifications

### 6.1 Color Usage

**Primary Blue (#1E40AF):**
- Navigation active state
- Primary buttons
- Data labels
- Links

**Amber CTA (#F59E0B):**
- Important actions (Create Plan, Edit)
- Warning indicators
- Pending status badges
- Chart highlights

**Status Colors:**
- Success/Active: #10B981 (Green)
- Failed/Error: #EF4444 (Red)
- Pending: #F59E0B (Amber)
- Cancelled: #6B7280 (Gray)

### 6.2 Typography Scale

```css
/* Headings - Fira Code */
h1: 32px / 2rem, font-weight: 700
h2: 24px / 1.5rem, font-weight: 600
h3: 20px / 1.25rem, font-weight: 600

/* Body - Fira Sans */
body: 16px / 1rem, font-weight: 400
small: 14px / 0.875rem, font-weight: 400
label: 14px / 0.875rem, font-weight: 500

/* Data/Code - Fira Code */
.data: 14px / 0.875rem, font-weight: 400, monospace
```

### 6.3 Component Specifications

**Metric Cards:**
```css
.metric-card {
  background: #1E293B; /* slate-800 */
  border-radius: 12px;
  padding: 24px;
  box-shadow: 0 4px 6px rgba(0,0,0,0.3);
}
.metric-value {
  font-family: 'Fira Code';
  font-size: 32px;
  color: #F59E0B; /* amber */
}
.metric-label {
  font-family: 'Fira Sans';
  font-size: 14px;
  color: #94A3B8; /* slate-400 */
}
```

**Data Tables:**
```css
.data-table {
  background: #1E293B;
  border-radius: 8px;
  overflow: hidden;
}
.table-header {
  background: #0F172A;
  color: #94A3B8;
  font-family: 'Fira Code';
  font-size: 12px;
  text-transform: uppercase;
  padding: 12px 16px;
}
.table-row {
  border-bottom: 1px solid #334155;
  padding: 12px 16px;
  transition: background 200ms;
}
.table-row:hover {
  background: #334155;
  cursor: pointer;
}
```

**Status Badges:**
```css
.badge {
  display: inline-block;
  padding: 4px 12px;
  border-radius: 12px;
  font-size: 12px;
  font-weight: 600;
  font-family: 'Fira Sans';
}
.badge-active { background: #10B98120; color: #10B981; }
.badge-pending { background: #F59E0B20; color: #F59E0B; }
.badge-failed { background: #EF444420; color: #EF4444; }
.badge-cancelled { background: #6B728020; color: #9CA3AF; }
```

**Buttons:**
```css
.btn-primary {
  background: #F59E0B;
  color: #0F172A;
  padding: 12px 24px;
  border-radius: 8px;
  font-weight: 600;
  font-family: 'Fira Sans';
  transition: all 200ms;
  cursor: pointer;
}
.btn-primary:hover {
  background: #D97706;
  transform: translateY(-1px);
}

.btn-secondary {
  background: transparent;
  color: #1E40AF;
  border: 2px solid #1E40AF;
  padding: 12px 24px;
  border-radius: 8px;
  font-weight: 600;
  transition: all 200ms;
  cursor: pointer;
}
```

### 6.4 Responsive Breakpoints

- Mobile: 375px - 767px (single column, stacked cards)
- Tablet: 768px - 1023px (2-column grid)
- Desktop: 1024px+ (full layout with sidebar)

### 6.5 Accessibility Requirements

- Minimum contrast ratio: 4.5:1 for all text
- Focus states visible on all interactive elements
- Keyboard navigation support (Tab order)
- ARIA labels on icon-only buttons
- Alt text on all images/charts
- Screen reader friendly table markup

---

## 7. Implementation Plan

### Phase 1: Backend API (Week 1)

**Tasks:**
1. Create admin API handlers in `internal/api/handlers/admin/`
2. Implement dashboard metrics aggregation
3. Add pagination helpers
4. Create admin router in `internal/api/router.go`
5. Add authentication middleware (basic auth for V1)

**Files to Create:**
- `internal/api/handlers/admin/dashboard_handler.go`
- `internal/api/handlers/admin/plan_handler.go`
- `internal/api/handlers/admin/subscription_handler.go`
- `internal/api/handlers/admin/charge_handler.go`
- `internal/api/handlers/admin/event_handler.go`
- `internal/api/middleware/admin_auth.go`

### Phase 2: Frontend Structure (Week 2)

**Tasks:**
1. Create HTML templates with Tailwind CSS
2. Implement navigation and routing (Alpine.js)
3. Build reusable components (cards, tables, badges)
4. Add Chart.js integration
5. Implement responsive layout

**Files to Create:**
- `web/admin/index.html` (dashboard)
- `web/admin/plans.html`
- `web/admin/subscriptions.html`
- `web/admin/charges.html`
- `web/admin/events.html`
- `web/admin/assets/css/admin.css`
- `web/admin/assets/js/admin.js`

### Phase 3: Feature Implementation (Week 3)

**Tasks:**
1. Dashboard metrics and charts
2. Plan management CRUD
3. Subscription monitoring with filters
4. Charge tracking with date ranges
5. Event log with real-time updates

### Phase 4: Testing & Polish (Week 4)

**Tasks:**
1. Manual testing of all features
2. Responsive design testing
3. Accessibility audit
4. Performance optimization
5. Documentation updates

---

## 8. Security Considerations

### 8.1 Authentication

**V1 Implementation:**
- Basic HTTP authentication
- Environment variable for admin credentials
- Single admin user

**Future Enhancements:**
- JWT-based authentication
- Role-based access control (RBAC)
- Multi-user support with permissions

### 8.2 Authorization

- All admin endpoints require authentication
- Read-only operations for monitoring
- Write operations only for plan management
- No direct subscription manipulation (use existing API)

### 8.3 Data Protection

- No sensitive data in logs
- Sanitize user inputs
- Parameterized SQL queries (already implemented)
- HTTPS required in production

---

## 9. Performance Considerations

### 9.1 Database Queries

- Add indexes for common filters:
  - `subscriptions(status, created_at)`
  - `charges(status, created_at)`
  - `events(event_type, created_at)`
- Use pagination for all list endpoints
- Cache dashboard metrics (5-minute TTL)

### 9.2 Frontend Optimization

- Lazy load charts (only render when visible)
- Debounce search inputs (300ms)
- Virtual scrolling for large tables
- Compress and minify assets

---

## 10. Monitoring & Logging

### 10.1 Admin Activity Logging

Log all admin actions:
- Plan creation/modification
- Filter/search queries
- Page views
- Export operations

### 10.2 Metrics to Track

- Admin page load times
- API endpoint response times
- Error rates by endpoint
- Most-used features

---

## 11. Future Enhancements

### 11.1 Phase 2 Features

- Export data to CSV/JSON
- Advanced filtering (date ranges, multi-select)
- Bulk operations (cancel multiple subscriptions)
- Email notifications for failed charges
- Webhook management interface

### 11.2 Phase 3 Features

- Real-time dashboard updates (WebSocket)
- Custom report builder
- Subscription analytics (churn rate, LTV)
- A/B testing for pricing
- Integration with external analytics tools

---

## 12. Appendix

### 12.1 Design System Reference

Full design system specifications: `design-system/market-blockchain-admin/MASTER.md`

### 12.2 API Reference

Existing API documentation: `market-blockchain/API.md`

### 12.3 Database Schema

Schema migrations: `market-blockchain/internal/store/migrations/`

---

**Document Status:** Draft  
**Last Updated:** 2026-04-23  
**Next Review:** After Phase 1 implementation
