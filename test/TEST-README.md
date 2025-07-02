# Jinks Templates Test Suite

This test suite validates the jinks-templates API using **Jest**, a popular JavaScript testing framework. It runs each example from `test-templates.json` against the API endpoint.

## File Structure

```
test/
├── app/                    # eXist-db test application
├── jest/                   # Jest testing framework files
│   ├── __tests__/         # Test files
│   │   └── api.test.js    # Main API tests
│   ├── jest.config.js     # Jest configuration
│   └── jest.setup.js      # Jest setup and custom matchers
├── run-tests.js           # Simple test runner script
└── TEST-README.md         # This documentation
```

## Prerequisites

- Node.js 14.0.0 or higher
- eXist-db running with jinks-templates-test app deployed
- The API endpoint should be accessible at `http://localhost:8080/exist/apps/jinks-templates-test/api/templates/`

## Setup

1. Install dependencies:
   ```bash
   npm install
   ```

2. Make sure your eXist-db instance is running
3. Deploy the jinks-templates-test app to eXist-db
4. Ensure the API endpoint is accessible

## Running the Tests

### Basic test run
```bash
npm test
```

### Watch mode (re-runs tests on file changes)
```bash
npm run test:watch
```

### Verbose output
```bash
npm run test:verbose
```

### With coverage report
```bash
npm run test:coverage
```

### Run specific test file
```bash
npx jest --config test/jest/jest.config.js test/jest/__tests__/api.test.js
```

### Run tests matching a pattern
```bash
npx jest --testNamePattern="HTML mode"
```

## What the Test Suite Does

1. **Loads** the `test-templates.json` file containing template examples
2. **Creates dynamic tests** for each template using Jest's test generation
3. **Sends** POST requests to the API endpoint with the template data
4. **Validates** responses using Jest assertions
5. **Groups tests** by functionality (API endpoint, template processing, modes, error handling)
6. **Provides detailed reporting** with Jest's built-in test runner

## Test Structure

The test suite is organized into several test groups:

- **API Endpoint**: Basic connectivity tests
- **Template Processing**: Individual tests for each template in `test-templates.json`
- **Template Modes**: Tests for different output modes (HTML, CSS, XQuery, Markdown)
- **Error Handling**: Tests for invalid inputs and error conditions

## Test Data Structure

Each test uses the following JSON structure:
```json
{
  "template": "template content here",
  "params": { "param1": "value1" },
  "mode": "html"
}
```

## Output

Jest provides rich output including:
- ✅ **Passing tests** with green checkmarks
- ❌ **Failing tests** with detailed error messages
- 📊 **Test summary** with execution time and coverage
- 🔍 **Detailed logs** for debugging failed tests

## Troubleshooting

### Connection Refused
- Ensure eXist-db is running
- Check that the port 8080 is correct
- Verify the app is deployed correctly

### 404 Not Found
- Check that the API endpoint path is correct
- Ensure the jinks-templates-test app is deployed

### 500 Internal Server Error
- Check the eXist-db logs for template processing errors
- Verify that the template syntax is valid

## Customization

You can modify the test suite by:
- Changing `API_BASE_URL` in `test-suite.js` for different endpoints
- Updating `SAMPLE_TEMPLATES_FILE` to use a different template file
- Adding additional validation logic in the `testTemplate` function 