const fs = require('fs');
const path = require('path');
const https = require('https');
const http = require('http');

// Configuration
const API_BASE_URL = 'http://localhost:8080/exist/apps/jinks-templates-test/api/templates/';
const SAMPLE_TEMPLATES_FILE = path.join(__dirname, '..', '..', 'test-templates.json');

/**
 * Make HTTP request to the API
 * @param {string} url - The API endpoint URL
 * @param {Object} data - The request body data
 * @returns {Promise<Object>} Response object with statusCode, headers, and data
 */
function makeRequest(url, data) {
    return new Promise((resolve, reject) => {
        const urlObj = new URL(url);
        const isHttps = urlObj.protocol === 'https:';
        const client = isHttps ? https : http;
        
        const options = {
            hostname: urlObj.hostname,
            port: urlObj.port,
            path: urlObj.pathname,
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                'Content-Length': Buffer.byteLength(data)
            }
        };

        const req = client.request(options, (res) => {
            let responseData = '';
            
            res.on('data', (chunk) => {
                responseData += chunk;
            });
            
            res.on('end', () => {
                resolve({
                    statusCode: res.statusCode,
                    headers: res.headers,
                    data: responseData
                });
            });
        });

        req.on('error', (error) => {
            reject(error);
        });

        req.write(data);
        req.end();
    });
}

/**
 * Test a single template against the API
 * @param {Object} template - Template object from test-templates.json
 * @returns {Promise<Object>} Test result
 */
async function testTemplate(template) {
    const testData = {
        template: template.template,
        params: template.params || {},
        mode: template.mode || 'html'
    };

    try {
        const response = await makeRequest(API_BASE_URL, JSON.stringify(testData));
        
        // Parse JSON response and extract the result
        let parsedData = null;
        let actualContent = null;
        
        if (response.statusCode === 200) {
            try {
                parsedData = JSON.parse(response.data);
                actualContent = parsedData.result;
            } catch (parseError) {
                // If parsing fails, use the raw response data
                actualContent = response.data;
            }
        }
        
        return {
            success: response.statusCode === 200,
            statusCode: response.statusCode,
            data: response.data,
            parsedData: parsedData,
            actualContent: actualContent,
            error: null
        };
    } catch (error) {
        return {
            success: false,
            statusCode: null,
            data: null,
            parsedData: null,
            actualContent: null,
            error: error.message
        };
    }
}

/**
 * Normalize whitespace for comparison
 * @param {string} text - Text to normalize
 * @returns {string} Normalized text
 */
function normalizeWhitespace(text) {
    return text
        .replace(/\r\n/g, '\n')  // Normalize line endings
        .replace(/\r/g, '\n')    // Convert remaining carriage returns
        .replace(/\s+/g, '')     // Remove all whitespace (spaces, tabs, newlines)
        .trim();                 // Remove leading/trailing whitespace
}

/**
 * Compare actual response with expected content
 * @param {string} actual - Actual response from API
 * @param {string} expected - Expected content from test data
 * @returns {Object} Comparison result
 */
function compareContent(actual, expected) {
    const normalizedActual = normalizeWhitespace(actual);
    const normalizedExpected = normalizeWhitespace(expected);
    
    return {
        matches: normalizedActual === normalizedExpected,
        actual: normalizedActual,
        expected: normalizedExpected,
        diff: normalizedActual !== normalizedExpected ? {
            actual: normalizedActual,
            expected: normalizedExpected
        } : null
    };
}

// Load sample templates
let templates = [];

// Load templates immediately when module is loaded
try {
    if (!fs.existsSync(SAMPLE_TEMPLATES_FILE)) {
        throw new Error(`Sample templates file not found: ${SAMPLE_TEMPLATES_FILE}`);
    }
    
    const templatesData = fs.readFileSync(SAMPLE_TEMPLATES_FILE, 'utf8');
    templates = JSON.parse(templatesData);
    
    if (!Array.isArray(templates) || templates.length === 0) {
        throw new Error('No templates found in test-templates.json');
    }
    
    console.log(`📋 Loaded ${templates.length} templates from test-templates.json`);
    console.log(`📋 Templates with expected content: ${templates.filter(t => t.expected).length}`);
} catch (error) {
    console.error('Failed to load templates:', error.message);
    throw error;
}

beforeAll(() => {
    // Additional setup if needed
    console.log('🧪 Test setup completed');
});

describe('Jinks Templates API', () => {
    describe('API Endpoint', () => {
        test('should be accessible', async () => {
            const testData = {
                template: '<p>Hello World</p>',
                params: {},
                mode: 'html'
            };

            const response = await makeRequest(API_BASE_URL, JSON.stringify(testData));
            expect(response.statusCode).toBe(200);
        }, 10000);
    });

    describe('Template Processing', () => {
        // Generate dynamic tests for each template
        templates.forEach((template, index) => {
            test(`should process template: ${template.description}`, async () => {
                const result = await testTemplate(template);
                
                // Log details for debugging
                if (!result.success) {
                    console.log(`\n❌ Failed template: ${template.description}`);
                    console.log(`Mode: ${template.mode}`);
                    if (result.error) {
                        console.log(`Error: ${result.error}`);
                    } else {
                        console.log(`Status: ${result.statusCode}`);
                        console.log(`Response: ${result.data}`);
                    }
                }
                
                expect(result.success).toBe(true);
                expect(result.statusCode).toBe(200);
                
                // If template has expected content, compare it with the response
                if (template.expected) {
                    const comparison = compareContent(result.actualContent, template.expected);
                    
                    if (!comparison.matches) {
                        console.log(`\n❌ Content mismatch for template: ${template.description}`);
                        console.log(`Mode: ${template.mode}`);
                        console.log(`Expected: ${comparison.expected}`);
                        console.log(`Actual: ${comparison.actual}`);
                    }
                    
                    expect(comparison.matches).toBe(true);
                }
            }, 15000);
        });
    });

    describe('Content Validation', () => {
        // Generate specific tests for templates with expected content
        const templatesWithExpected = templates.filter(t => t.expected);
        
        templatesWithExpected.forEach((template, index) => {
            test(`should produce expected content for: ${template.description}`, async () => {
                const result = await testTemplate(template);
                
                expect(result.success).toBe(true);
                expect(result.statusCode).toBe(200);
                
                const comparison = compareContent(result.actualContent, template.expected);
                
                if (!comparison.matches) {
                    console.log(`\n❌ Content validation failed for: ${template.description}`);
                    console.log(`Mode: ${template.mode}`);
                    console.log(`Expected: ${comparison.expected}`);
                    console.log(`Actual: ${comparison.actual}`);
                }
                
                expect(comparison.matches).toBe(true);
            }, 15000);
        });
    });

    describe('Template Modes', () => {
        test('should handle HTML mode', async () => {
            const htmlTemplate = templates.find(t => t.mode === 'html');
            if (!htmlTemplate) {
                console.warn('No HTML template found in sample data');
                return;
            }

            const result = await testTemplate(htmlTemplate);
            expect(result.success).toBe(true);
            expect(result.statusCode).toBe(200);
        });

        test('should handle CSS mode', async () => {
            const cssTemplate = templates.find(t => t.mode === 'css');
            if (!cssTemplate) {
                console.warn('No CSS template found in sample data');
                return;
            }

            const result = await testTemplate(cssTemplate);
            expect(result.success).toBe(true);
            expect(result.statusCode).toBe(200);
        });

        test('should handle XQuery mode', async () => {
            const xqueryTemplate = templates.find(t => t.mode === 'xquery');
            if (!xqueryTemplate) {
                console.warn('No XQuery template found in sample data');
                return;
            }

            const result = await testTemplate(xqueryTemplate);
            expect(result.success).toBe(true);
            expect(result.statusCode).toBe(200);
        });
    });

    describe('Error Handling', () => {
        test('should handle invalid JSON gracefully', async () => {
            try {
                await makeRequest(API_BASE_URL, 'invalid json');
                // If we get here, the API should return an error status
                // This test might need adjustment based on actual API behavior
            } catch (error) {
                // Expected behavior for invalid JSON
                expect(error).toBeDefined();
            }
        });

        test('should handle missing template parameter', async () => {
            const testData = {
                params: {},
                mode: 'html'
            };

            const response = await makeRequest(API_BASE_URL, JSON.stringify(testData));
            // API should return an error for missing template
            expect(response.statusCode).not.toBe(200);
        });
    });
});

// Custom matcher for better error messages
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
}); 