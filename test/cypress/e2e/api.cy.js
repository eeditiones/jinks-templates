/// <reference types="cypress" />

describe('Jinks Templates API - General API Contract', () => {
  it('should respond to a minimal valid request', () => {
    cy.request({
      method: 'POST',
      url: '/',
      body: {
        template: '<p>Hello World</p>',
        params: {},
        mode: 'html'
      },
      failOnStatusCode: false
    }).then(response => {
      expect(response.status).to.eq(200)
      // Optionally check response structure
      expect(response.body).to.have.property('result')
    })
  })

  it('should return error for invalid JSON', () => {
    cy.request({
      method: 'POST',
      url: '/',
      body: 'invalid json',
      failOnStatusCode: false,
      headers: { 'Content-Type': 'application/json' }
    }).then(response => {
      expect(response.status).not.to.eq(200)
      // Optionally check error message
    })
  })

  it('should return error for missing template parameter', () => {
    cy.request({
      method: 'POST',
      url: '/',
      body: {
        params: {},
        mode: 'html'
      },
      failOnStatusCode: false
    }).then(response => {
      expect(response.status).not.to.eq(200)
      expect(response.body).to.contain('ERROR')
    })
  })

  it('should process template when params is omitted', () => {
    cy.request({
      method: 'POST',
      url: '/',
      body: {
        template: '<p>Hello World</p>',
        mode: 'html'
        // params is omitted
      },
      failOnStatusCode: false
    }).then(response => {
      expect(response.status).to.eq(200)
      expect(response.body).to.have.property('result')
    })
  })

  it('should return error for malformed template syntax', () => {
    cy.request({
      method: 'POST',
      url: '/',
      body: {
        template: '<div>[% if $foo %]bar', // missing endif and closing tag
        params: {},
        mode: 'html'
      },
      failOnStatusCode: false
    }).then(response => {
      expect(response.status).not.to.eq(200)
      expect(response.body).to.contain('Missing endif')
    })
  })

  // see #13
  it('should treat invalid mode as xml', () => {
    cy.request({
      method: 'POST',
      url: '/',
      body: {
        template: '<p>Hello World</p>',
        params: {},
        mode: 'foobar' // invalid mode
      },
      failOnStatusCode: false
    }).then(response => {
      expect(response.status).to.eq(200)
      expect(response.body).to.have.property('result')
    })
  })
})