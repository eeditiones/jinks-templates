/// <reference types="cypress" />
describe('CSS mode should', () => {
    it('apply expected style', () => {
      cy.request({
        method: 'POST',
        url: '/',
        body: {
          template: '[% if $logo %]\n.logo {\n    background-image: url("[[ $logo ]]");\n}\n[% endif %]\n\nbody {\n  --pb-base-font-family: [[ $font ]];\n  --pb-content-font-family: [[ $contentFont ]];\n}',
          params: {logo: '../images/tei-publisher-logo-color.svg', font: 'Helvetica', contentFont: 'Times'},
          mode: 'css'
        },
        failOnStatusCode: false
      }).then(response => {
        expect(response.status).to.eq(200)
        expect(response.body).to.have.property('result')
        const css = response.body.result

        cy.document().then(doc => {
          // Inject CSS into the DOM
          const style = doc.createElement('style')
          style.innerHTML = css
          doc.head.appendChild(style)

          // Add a test element with the relevant class
          const el = doc.createElement('div')
          el.className = 'logo'
          doc.body.appendChild(el)

          // Assert the computed style
          cy.get('.logo').should('have.css', 'background-image').and('include', 'tei-publisher-logo-color.svg')
          // Optionally, check CSS custom properties on body
          cy.get('body').should('have.css', '--pb-base-font-family', 'Helvetica')
          cy.get('body').should('have.css', '--pb-content-font-family', 'Times')
        })
      })
    })
  })