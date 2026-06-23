/// <reference types="cypress" />

describe('Template Content in plain text mode should', () => {
    it('emit conditional attributes without leaking values as text', () => {
      const template = '<package>\n' +
        '  [% for $dep in $dependencies?* %]\n' +
        '    <dependency package="[[$dep?package]]" semver="![[$dep?semver]]" semver-min="![[$dep?semver-min]]" semver-max="![[$dep?semver-max]]"/>\n' +
        '  [% endfor %]\n' +
        '</package>'
      const expected = '<package>\n' +
        '\n' +
        '    <dependency package="http://example.org/a" semver="1"/>\n' +
        '\n' +
        '    <dependency package="http://example.org/b" semver-min="6.1" semver-max="6"/>\n' +
        '\n' +
        '</package>'

      cy.request({
        method: 'POST',
        url: '/',
        body: {
          template,
          params: {
            dependencies: [
              { package: 'http://example.org/a', semver: '1' },
              { package: 'http://example.org/b', 'semver-min': '6.1', 'semver-max': '6' }
            ]
          },
          mode: 'text'
        },
        failOnStatusCode: false
      }).then(response => {
        expect(response.status).to.eq(200)
        expect(response.body).to.have.property('result')
        expect(response.body.result.replace(/^[ \t]+$/gm, '')).to.eq(expected)
      })
    })
})
