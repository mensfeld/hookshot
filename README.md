# Hookshot

A self-hosted webhook relay service built with Rails 8. Receives webhooks, filters them based on configurable rules, and dispatches to multiple target endpoints.

## Quick Start

```bash
# Clone and install
git clone https://github.com/mensfeld/hookshot.git
cd hookshot
bundle install
npm install

# Setup database and assets
rails db:create db:migrate
rails tailwindcss:build

# Start everything (web + background jobs)
./bin/dev

# Or start separately:
# rails server          # Web server on port 3000
# rails solid_queue:start  # Background job processor
```

Then:
1. Visit `http://localhost:3000/admin/targets` (login: `admin` / `changeme`)
2. Create a target with your destination URL
3. Send webhooks to `http://localhost:3000/webhooks/receive`

## Features

- **Webhook Reception**: Accepts POST requests at `/webhooks/receive` and stores headers, payload, and metadata
- **Multiple Targets**: Configure multiple destination endpoints for webhook delivery
- **Filtering**: Route webhooks to specific targets based on header or payload content
- **Background Processing**: Reliable delivery with Solid Queue, including retries with exponential backoff
- **Admin Dashboard**: View webhooks, dispatches, and manage targets with a clean DaisyUI interface
- **Replay**: Re-dispatch any webhook to all active targets
- **Health Check**: `/health` endpoint for monitoring

## Requirements

- Ruby 3.4+
- SQLite 3
- Node.js (for Tailwind CSS compilation)

## Setup

```bash
# Install dependencies
bundle install
npm install

# Setup database
rails db:create db:migrate

# Compile assets
rails tailwindcss:build

# Start the server
rails server
```

## Configuration

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `HOOKSHOT_USER` | `admin` | HTTP Basic Auth username for admin UI |
| `HOOKSHOT_PASSWORD` | `changeme` | HTTP Basic Auth password for admin UI |
| `RETENTION_DAYS` | `30` | Days to retain webhook data before cleanup |

### Background Jobs

Start Solid Queue to process webhook deliveries:

```bash
rails solid_queue:start
```

Or run everything with Foreman/Overmind using the Procfile.

## Usage

### Receiving Webhooks

Send any POST request to `/webhooks/receive`:

```bash
curl -X POST http://localhost:3000/webhooks/receive \
  -H "Content-Type: application/json" \
  -d '{"event": "user.created", "data": {"id": 123}}'
```

### Admin Dashboard

Access the admin UI at `http://localhost:3000/admin/webhooks` with HTTP Basic Auth.

- **Webhooks**: View received webhooks, inspect headers/payload, replay to targets
- **Dispatches**: Monitor delivery status, retry failed deliveries
- **Targets**: Configure destination endpoints with filters
- **Jobs**: Solid Queue dashboard at `/jobs`

### Configuring Targets

Each target has:

- **Name**: Identifier for the target
- **URL**: Destination endpoint (must be HTTPS in production)
- **Timeout**: Request timeout in seconds (1-300)
- **Active**: Toggle to enable/disable delivery
- **Custom Headers**: Additional headers to send with each request
- **Filters**: Rules to determine which webhooks to deliver

### Filters

Filters allow routing webhooks to specific targets. All filters must match for delivery.

**Filter Types:**
- `Header`: Match against request headers
- `Payload`: Match against JSON payload using dot notation (e.g., `$.event`)

**Operators:**
- `Exists`: Field is present
- `Equals`: Field equals exact value
- `Matches`: Field matches pattern (supports `*` wildcard)

**Example**: Only deliver webhooks where `$.event` equals `user.created`:
- Type: `Payload`
- Field: `$.event`
- Operator: `Equals`
- Value: `user.created`

## API Endpoints

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| POST | `/webhooks/receive` | None | Receive incoming webhooks |
| GET | `/health` | None | Health check endpoint |
| GET | `/admin/*` | Basic | Admin dashboard |
| GET | `/jobs` | Basic | Solid Queue dashboard |

## Delivery Headers

Each delivery includes these headers:

- `Content-Type`: Original webhook content type
- `X-Hookshot-Webhook-Id`: Internal webhook ID
- `X-Hookshot-Delivery-Id`: Internal delivery ID
- Any custom headers configured on the target

## Retry Behavior

Failed deliveries are retried with exponential backoff:

- Up to 5 attempts
- Increasing delay between retries
- Client errors (4xx) are not retried
- Server errors (5xx) and timeouts are retried

## Docker Deployment

Single container runs both web server and background job processor:

```bash
# Build image
docker build -t hookshot .

# Run with docker-compose
SECRET_KEY_BASE=$(rails secret) HOOKSHOT_PASSWORD=your-password docker-compose up -d

# Or run directly
docker run -d \
  -p 3000:3000 \
  -v hookshot_data:/rails/storage \
  -e SECRET_KEY_BASE=$(rails secret) \
  -e HOOKSHOT_PASSWORD=your-password \
  --name hookshot \
  hookshot
```

Data is persisted in the `hookshot_data` volume.

## Development

```bash
# Run tests with coverage report
bundle exec rspec
# Coverage report generated at coverage/index.html

# Run linter
bundle exec rubocop

# Check documentation coverage
bundle exec yard-lint app/

# Watch for CSS changes
rails tailwindcss:watch
```

### Code Quality

- **RSpec** with 85% minimum line and branch coverage (SimpleCov)
- **RuboCop** with Rails Omakase style
- **yard-lint** for YARD documentation validation

### CI

GitHub Actions runs on every push/PR:
- Test suite with coverage enforcement
- RuboCop linting
- YARD documentation validation

## License

MIT
