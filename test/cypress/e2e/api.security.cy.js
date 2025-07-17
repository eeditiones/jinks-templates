/// <reference types="cypress" />

describe('Jinks Templates API - Security', () => {
  it('should not execute or return raw script tags in params', () => {
    cy.request({
      method: 'POST',
      url: '/',
      body: {
        template: '<div>[[ $userInput ]]</div>',
        params: { userInput: '<script>alert("xss")</script>' },
        mode: 'html'
      },
      failOnStatusCode: false
    }).then(response => {
      expect(response.status).to.eq(200)
      expect(response.body.result).not.to.contain('<script>alert("xss")</script>')
      // Optionally, check for escaped output or safe handling
    })
  })


  it('should not allow path traversal in includes', () => {
    cy.request({
      method: 'POST',
      url: '/',
      body: {
        template: '[% include "../../../../etc/passwd" %]',
        params: {},
        mode: 'html'
      },
      failOnStatusCode: false
    }).then(response => {
      expect(response.status).not.to.eq(200)
      expect(response.body).not.to.contain('root:')
    })
  })

  it('should ignore unexpected and spoofed headers', () => {
    const maliciousHeaders = {
      'X-Forwarded-For': 'evil.com',
      'X-Api-Key': 'malicious',
      'Authorization': 'Bearer totally-fake-token'
    }
    cy.request({
      method: 'POST',
      url: '/',
      body: {
        template: '<p>Hello</p>',
        params: {},
        mode: 'html'
      },
      headers: maliciousHeaders,
      failOnStatusCode: false
    }).then(response => {
      expect(response.status).to.eq(200)
      expect(response.body).to.have.property('result')
      // Ensure none of the malicious header values are reflected in the response
      Object.values(maliciousHeaders).forEach(val => {
        expect(JSON.stringify(response.body)).not.to.contain(val)
      })
      // Optionally, check response headers for absence of these values
      Object.keys(maliciousHeaders).forEach(header => {
        if (response.headers[header.toLowerCase()]) {
          expect(response.headers[header.toLowerCase()]).not.to.contain(maliciousHeaders[header])
        }
      })
    })
  })
}) 