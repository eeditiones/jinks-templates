// Global test setup
beforeAll(() => {
  // Increase timeout for all tests
  jest.setTimeout(30000);
  
  // Log test environment
  console.log('\n🧪 Starting Jinks Templates API Tests');
  console.log('API Endpoint: http://localhost:8080/exist/apps/jinks-templates-test/api/templates/');
  console.log('Make sure eXist-db is running and the app is deployed!\n');
});

// Global test teardown
afterAll(() => {
  console.log('\n✅ All tests completed');
});

// Custom matchers
expect.extend({
  toBeSuccessfulResponse(received) {
    const pass = received.success && received.statusCode === 200;
    if (pass) {
      return {
        message: () => `expected response to not be successful`,
        pass: true,
      };
    } else {
      return {
        message: () => 
          `expected response to be successful but got status ${received.statusCode}${received.error ? ` with error: ${received.error}` : ''}`,
        pass: false,
      };
    }
  },
  
  toHaveValidStatus(received) {
    const pass = received.statusCode >= 200 && received.statusCode < 300;
    if (pass) {
      return {
        message: () => `expected status to not be valid`,
        pass: true,
      };
    } else {
      return {
        message: () => `expected status to be valid but got ${received.statusCode}`,
        pass: false,
      };
    }
  }
});

// Global error handler for unhandled promise rejections
process.on('unhandledRejection', (reason, promise) => {
  console.error('Unhandled Rejection at:', promise, 'reason:', reason);
}); 