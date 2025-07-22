/// <reference types="cypress" />
describe('XQuery mode should', () => {
    function normalizeWhitespace(str) {
      return str
        .replace(/\r\n/g, '\n')  // Normalize line endings
        .replace(/\r/g, '\n')    // Convert remaining carriage returns
        .replace(/\s+/g, '')     // Remove all whitespace (spaces, tabs, newlines)
        .trim()                 // Remove leading/trailing whitespace
    }
    
    it('produce expected content', () => {
      const expected = 'declare variable $config:webcomponents := "2.19.0";declare variable $config:data-root := $config:app-root || "/data";'
      cy.request({
        method: 'POST',
        url: '/',
        body: {
          template: 'declare variable $config:webcomponents := "[[$webcomponents]]";\n\ndeclare variable $config:data-root := \n  [% if $data-root %]\n  "[[ $data-root ]]"\n  [% elif $alternate-root %]\n  "[[ $alternate-root ]]"\n  [% else %]\n  $config:app-root || "/data"\n  [% endif %];',
          params: {webcomponents: '2.19.0', 'data-root': null, 'alternate-root': null},
          mode: 'xquery'
        },
        failOnStatusCode: false
      }).then(response => {
        expect(response.status).to.eq(200)
        expect(response.body).to.have.property('result')
        expect(normalizeWhitespace(response.body.result)).to.eq(normalizeWhitespace(expected))
      })
    })
  })