#!/bin/bash

# Test script that mimics the GitHub Actions workflow locally
# This script builds the Docker image, starts the container, and runs the test suite

set -e  # Exit on any error

echo "🧪 Starting local Docker test workflow..."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

# Check if Docker is running
if ! docker info > /dev/null 2>&1; then
    print_error "Docker is not running. Please start Docker and try again."
    exit 1
fi

# Check if Node.js is installed
if ! command -v node &> /dev/null; then
    print_error "Node.js is not installed. Please install Node.js 14.0.0 or higher."
    exit 1
fi

# Check if npm is installed
if ! command -v npm &> /dev/null; then
    print_error "npm is not installed. Please install npm."
    exit 1
fi

print_status "Prerequisites check passed"

# Install dependencies
print_status "Installing npm dependencies..."
npm ci

# Build Docker image
print_status "Building Docker image..."
docker build -t jinks-templates-test .

# Clean up any existing container with the same name
print_status "Cleaning up any existing containers..."
docker stop jinks-templates-test-container 2>/dev/null || true
docker rm jinks-templates-test-container 2>/dev/null || true

# Start container
print_status "Starting eXist-db container..."
docker run -d \
    --name jinks-templates-test-container \
    -p 8080:8080 \
    -p 8443:8443 \
    jinks-templates-test

# Wait for eXist-db to be ready
print_status "Waiting for eXist-db to start..."
timeout=180
counter=0
while [ $counter -lt $timeout ]; do
    if curl -f http://localhost:8080/exist/ > /dev/null 2>&1; then
        print_status "eXist-db is ready!"
        break
    fi
    echo "⏳ Waiting for eXist-db... ($counter/$timeout seconds)"
    sleep 5
    counter=$((counter + 5))
done

if [ $counter -eq $timeout ]; then
    print_error "Timeout waiting for eXist-db to start"
    echo "Container logs:"
    docker logs jinks-templates-test-container
    exit 1
fi

# Wait for app to be deployed
print_status "Waiting for app to be deployed..."
timeout=120
counter=0
while [ $counter -lt $timeout ]; do
    if curl -f -X POST http://localhost:8080/exist/apps/jinks-templates-test/api/templates/ \
        -H "Content-Type: application/json" \
        -d '{"template":"<p>test</p>","params":{},"mode":"html"}' > /dev/null 2>&1; then
        print_status "App is deployed and ready!"
        break
    fi
    echo "⏳ Waiting for app deployment... ($counter/$timeout seconds)"
    sleep 3
    counter=$((counter + 3))
done

if [ $counter -eq $timeout ]; then
    print_error "Timeout waiting for app to be deployed"
    echo "Container logs:"
    docker logs jinks-templates-test-container
    echo "Testing API endpoint:"
    curl -v -X POST http://localhost:8080/exist/apps/jinks-templates-test/api/templates/ \
        -H "Content-Type: application/json" \
        -d '{"template":"<p>test</p>","params":{},"mode":"html"}' || true
    exit 1
fi

# Test API connectivity
print_status "Testing API connectivity..."
curl -X POST http://localhost:8080/exist/apps/jinks-templates-test/api/templates/ \
    -H "Content-Type: application/json" \
    -d '{"template":"<p>Hello World</p>","params":{},"mode":"html"}' \
    -w "\nHTTP Status: %{http_code}\n"

# Run test suite
print_status "Running test suite..."
npm test

print_status "All tests completed successfully!"

# Ask user if they want to keep the container running
echo ""
read -p "Do you want to keep the container running for further testing? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    print_warning "Container is still running. You can access the API at http://localhost:8080"
    print_warning "To stop the container later, run: docker stop jinks-templates-test-container"
    print_warning "To remove the container later, run: docker rm jinks-templates-test-container"
else
    # Cleanup
    print_status "Cleaning up..."
    docker stop jinks-templates-test-container
    docker rm jinks-templates-test-container
    docker rmi jinks-templates-test
    print_status "Cleanup completed"
fi

print_status "Local test workflow completed successfully!" 