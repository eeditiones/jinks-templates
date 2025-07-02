module.exports = {
  // Test environment
  testEnvironment: 'node',
  
  // Test timeout (30 seconds for API calls)
  testTimeout: 30000,
  
  // Verbose output
  verbose: true,
  
  // Collect coverage
  collectCoverage: false,
  collectCoverageFrom: [
    '**/*.js',
    '!**/node_modules/**',
    '!**/coverage/**',
    '!jest.config.js',
    '!package.json'
  ],
  
  // Coverage thresholds
  coverageThreshold: {
    global: {
      branches: 80,
      functions: 80,
      lines: 80,
      statements: 80
    }
  },
  
  // Test file patterns
  testMatch: [
    '**/__tests__/**/*.test.js',
    '**/?(*.)+(spec|test).js'
  ],
  
  // Setup files
  setupFilesAfterEnv: ['<rootDir>/jest.setup.js'],
  
  // Reporter
  reporters: [
    'default',
    ['jest-junit', {
      outputDirectory: 'coverage',
      outputName: 'junit.xml',
      classNameTemplate: '{classname}',
      titleTemplate: '{title}',
      ancestorSeparator: ' › ',
      usePathForSuiteName: true
    }]
  ],
  
  // Clear mocks between tests
  clearMocks: true,
  
  // Restore mocks between tests
  restoreMocks: true,
  
  // Module file extensions
  moduleFileExtensions: ['js', 'json'],
  
  // Transform
  transform: {},
  
  // Globals
  globals: {
    'ts-jest': {
      useESM: true
    }
  }
}; 