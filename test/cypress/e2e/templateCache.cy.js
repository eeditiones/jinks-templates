/// <reference types="cypress" />

// tmpl:process with the "cache" option keeps compiled templates in an eXist
// cache. Each test runs a template twice or more through the same cache, so the
// later calls are served from it, and checks every result.
describe('Templates compiled into a cache should', () => {
  const cache = `cypress-template-cache-${Date.now()}`

  const expand = (template, params, mode = 'html', useCache = true) => cy.request({
    method: 'POST',
    url: '/',
    body: useCache ? { template, params, mode, cache } : { template, params, mode },
    failOnStatusCode: false
  })

  it('use each call\'s param values, not the first call\'s', () => {
    const template = '<div><p>[[ $greeting ]], [[ $name ]]!</p></div>'
    const runs = [
      [{ greeting: 'Hello', name: 'world' }, '<div><p>Hello, world!</p></div>'],
      [{ greeting: 'Goodbye', name: 'cache' }, '<div><p>Goodbye, cache!</p></div>'],
      [{ greeting: 'Hello', name: 'again' }, '<div><p>Hello, again!</p></div>']
    ]
    runs.forEach(([params, expected]) => {
      expand(template, params).then(response => {
        expect(response.status).to.eq(200)
        expect(response.body.result).html.to.equal(expected)
      })
    })
  })

  it('compile a template again when its params have other names', () => {
    // the generated code binds a variable per param, so other names need other code
    const template = '<div><p>[[ string-join(sort(map:keys($context)), " ") ]]</p></div>'
    const paramSets = [{ other: 1 }, { extra: 'present', other: 2 }, { other: 3 }]
    paramSets.forEach(params => {
      expand(template, params, 'html', false).then(uncached => {
        expect(uncached.status).to.eq(200)
        expand(template, params).then(cached => {
          expect(cached.status).to.eq(200)
          expect(cached.body.result).html.to.equal(uncached.body.result)
        })
      })
    })
  })

  it('give the same result as without the cache for extends, use and include', () => {
    const template = '---json\n{\n  "title": "Lorem ipsum dolor sit amet",\n  "templating": {\n    "extends": "pages/base.html",\n    "use": ["pages/blocks.html"]\n  }\n}\n---\n[% template menu %]\n<li>Extra menu item</li>\n[% endtemplate %]\n[% template copyright %]\n<p>© e-editiones</p>\n[% endtemplate %]\n<div>\n  <p>[[ $title ]]</p>\n  [% block foo %]\n  <p>A block with a default content.</p>\n  [% endblock %]\n</div>'
    expand(template, {}, 'html', false).then(uncached => {
      expect(uncached.status).to.eq(200)
      for (let i = 0; i < 3; i++) {
        expand(template, {}).then(cached => {
          expect(cached.status).to.eq(200)
          expect(cached.body.result).html.to.equal(uncached.body.result)
        })
      }
    })
  })

  it('let params override frontmatter the same way when cached', () => {
    const template = '---json\n{ "title": "From the frontmatter" }\n---\n<h1>[[ $title ]]</h1>'
    expand(template, { title: 'From the params' }, 'html', false).then(uncached => {
      expand(template, { title: 'From the params' }).then(first => {
        expect(first.body.result).html.to.equal(uncached.body.result)
      })
      expand(template, { title: 'From other params' }).then(second => {
        expect(second.status).to.eq(200)
        expect(second.body.result).html.to.equal(uncached.body.result.replace('From the params', 'From other params'))
      })
    })
  })

  it('work in plain text mode', () => {
    const template = 'Total: [[ sum($values?*) ]]'
    expand(template, { values: [1, 2, 3] }, 'text').then(response => {
      expect(response.status).to.eq(200)
      expect(response.body.result).to.equal('Total: 6')
    })
    expand(template, { values: [10, 20] }, 'text').then(response => {
      expect(response.status).to.eq(200)
      expect(response.body.result).to.equal('Total: 30')
    })
  })
})
