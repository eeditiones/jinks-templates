# Jinks Templates

A modern templating engine for eXist-db that brings the full power of XPath and XQuery to template processing. Built for flexibility and performance, Jinks Templates handles HTML, XML, CSS, XQuery, and plain text files with a unified syntax.

## Overview

Jinks Templates was developed as the core templating engine for _Jinks_, the new app generator for _TEI Publisher_. It extends beyond eXist's older HTML templating capabilities to provide a comprehensive solution for any templating task in the eXist ecosystem.

## Key Features

**🎯 Universal Processing** - Handle any file type with a single templating engine

**⚡ Native XPath/XQuery** - Use familiar XPath expressions directly in templates

**🏗️ Robust Architecture** - AST-based parsing and compilation for better performance

**📝 Frontmatter Support** - Extend template context with embedded configuration

**🔧 Developer Experience** - Familiar syntax inspired by Nunjucks and JSX

## Architecture

Jinks Templates employs a sophisticated two-stage processing pipeline:

1. **Parser** - Converts templates into an XML-based Abstract Syntax Tree
2. **Compiler** - Transforms the AST into optimized XQuery code

This architecture delivers superior performance, comprehensive error handling, and enhanced debugging capabilities compared to traditional regex-based solutions.

## Expressions

The template syntax is similar to [nunjucks](https://mozilla.github.io/nunjucks/) or [jinja](https://jinja.palletsprojects.com/en/3.1.x/templates/), but uses the host language for all expressions, therefore giving users the full power of XPath/XQuery.

The templating is passed a context map, which should contain all the information necessary for processing the template expressions. The entire context map can be accessed via variable `$context`. Additionally, each top-level property in the context map is made available as an XQuery variable. So if you have a context map like

```xquery
map {
    "title": "my title",
    "theme": map {
        "fonts": map {
            "content": "serif"
        }
    }
}
```

you can either use a value expression `[[ $context?title ]]` or the shorter form `[[ $title ]]` to output the title. And to insert the content font, use `[[ $context?theme?fonts?content ]]` or `[[ $theme?fonts?content ]]`.

**Note**: trying to access an undefined context property via the short form, e.g. `[[ $author ]]`, will result in an error. So in case you are unsure if a property is defined, use the long form, i.e. `[[ $context?author ]]`.

Supported template expressions are:

| Expression | Description |
| -------- | ------- |
| `[[ expr ]]` | Insert result of evaluating `expr` |
| `[% if expr %] … [% endif %]` | Conditional evaluation of block |
| `… [% elif expr %] …` | *else if* block after *if* |
| `… [% else %] … [% endif %]` | *else* block after *if* or *else if* |
| `[% for $var in expr %] … [% endfor %]` | Loop `$var` over sequence returned by `expr` |
| `[% include expr %]` | Include a partial. `expr` should resolve to relative path. |
| `[% block name %] … [% endblock %]` | Defines a named block, optionally containing default content to be displayed if there's no `template` addressing this block.|
| `[% template name %] … [% endtemplate %]` | Contains content to be appended to the block with the same name. |
| `[% import "uri" as "prefix" at "path" %]` | Import an XQuery module so its functions/variables can be used in template expressions. |
| `[% raw %]…[% endraw %]` | Include the contained text as is, without parsing for templating expressions |
| `[# … #]` | Single or multi-line comment: content will be discarded |

`expr` must be a valid XPath expression.

For some real pages built with jinks-templates, check the main [jinks app manager](https://github.com/eeditiones/jinks/tree/main/pages). This app also includes a playground and demo for jinks-templates.

## Output Modes

The library supports two modes: **XML/HTML** and **plain text**. They differ in the XQuery code templates are compiled into. While the first will always return XML – and fails if the result is not well-formed, the second uses XQuery string templates.

## Use in XQuery

The library exposes one main function, `tmpl:process`, which takes 3 arguments:

1. `xs:string`: the template to process as a string
2. `map(*)`: the context providing the information to be passed to templating expressions
3. `map(*)`: a configuration map with the following properties:
   1. `plainText` (`xs:boolean?`): should be true for plain text processing (default is false)
   2. `resolver` (`function(xs:string)?`): the resolver function to use (see below)
   3. `modules` (`map(*)?`): sequence of modules to import (see below)
   4. `namespaces` (`map(*)?`): namespace mappings (see below)
   5. `debug` (`xs:boolean?`): if true, `tmpl:process` returns a map with the result, ast and generated XQuery code (default is false)

A simple example:

```xquery
xquery version "3.1";

import module namespace tmpl="http://e-editiones.org/xquery/templates";

let $input :=
    <body>
        <h1>[[$title]]</h1>
        <p>You are running eXist [[system:get-version()]]</p>
    </body>
    => serialize()
let $context := map {
    "title": "My app"
}
return
    tmpl:process($input, $context, map { "plainText": false() })
```

The input is constructed as XML, but serialized into a string for the call to `tmpl:process`. The context map contains a single property, which will become available as variable `$title` within template expressions.

### Specifying a resolver

The `resolver` function is needed if you would like to use `[% include %]`, `[% extends %]` or `[% import %]` in your templates. It should point to a function with one parameter: the relative path to the resource, and should return a map with two fields:

* `path`: the absolute path to the resource
* `content`: the content of the resource as a string

If the resource cannot be resolved, the empty sequence should be returned. In the following example we're prepending the assumed application root (`$config:app-root`) to get an absolute path and load the resource:

```xquery
import module namespace tmpl="http://e-editiones.org/xquery/templates";
import module namespace config=...;

declare function local:resolver($relPath as xs:string) as map(*)? {
    let $path := $config:app-root || "/" || $relPath
    let $content :=
        if (util:binary-doc-available($path)) then
            util:binary-doc($path) => util:binary-to-string()
        else if (doc-available($path)) then
            doc($path) => serialize()
        else
            ()
    return
        if ($content) then
            map {
                "path": $path,
                "content": $content
            }
        else
            ()
};

let $input :=
    <body>
        <h1>[[$title]]</h1>
        <p>You are running eXist [[system:get-version()]]</p>
    </body>
    => serialize()
let $context := map {
    "title": "My app"
}
let $config := map {
    "resolver": local:resolver#1
}
return
    tmpl:process($input, $context, $config)
```

### Importing XQuery modules

To make the variables and functions of specific XQuery modules available in your templates, you have to explicitely list those in the configuration using property `modules`. This is a map in which the key of each entry corresponds to the URI of the module and the value is a map with two properties: `prefix` and `at`, specifying the prefix to use and the location from which the module can be loaded:

```xquery
let $config := map {
    "resolver": local:resolver#1,
    "modules": map {
        "http://www.tei-c.org/tei-simple/config": map {
            "prefix": "config",
            "at": $config:app-root || "/modules/config.xqm"
        }
    },
    "namespaces": map {
      "tei": "http://www.tei-c.org/ns/1.0"
    }
}
return
    tmpl:process($input, $context, $config)
```

As shown above you can also declare namespaces via the configuration in a simple object using the desired prefix as key and the namespace URI as value.

## Use frontmatter to extend the context

Templates may start with a frontmatter block enclosed in `---`. The purpose of the frontmatter is to extend or overwrite the static context map provided in the second argument to `tmpl:process`. Currently only JSON syntax is supported. The frontmatter block will be parsed into an JSON object and merged with the static context passed to `tmpl:process`. For example, take the following template:

```html
---json
{
  "title": "Lorem ipsum dolor sit amet",
  "author": "Hans"
}
---
<article>
<h1>[[ $title ]]</h1>

<p>Consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum.</p>

<footer>Published [[format-date(current-dateTime(), "[MNn] [D], [Y]", "en", (), ())]] by [[$author]].</footer>
</article>
```

This will overwrite the `title` and `author` properties of the static context map. The frontmatter block should come first in the file with a newline after each of the two separators. However, to allow for well-formed XML, the frontmatter may come *after* one or more surrounding elements, e.g.:

```html
<article>
---json
{
  "title": "Lorem ipsum dolor sit amet",
  "author": "Hans"
}
---
<h1>[[ $title ]]</h1>
</article>
```

## Configuring the templating in frontmatter

Some of the configuration parameters for the templating can also be set via the frontmatter instead of providing them to the `tmpl:process` XQuery function. In particular this includes `modules`, `namespaces`. 

Additionally, you can enable template inheritance in the frontmatter using `extends` (see next section).

Templating configuration parameters should go below a top-level property named `templating`:

```html
---json
{
  "templating": {
    "extends": "pages/demo/base.html",
    "namespaces": {
      "tei": "http://www.tei-c.org/ns/1.0"
    },
    "modules": {
      "https://tei-publisher.com/jinks/xquery/demo": {
        "prefix": "demo",
        "at": "modules/demo.xql"
      }
    }
  }
}
---

<article>
[% let $data = demo:tei() %]
<h1>[[ $data//tei:title/text() ]]</h1>
<p>[[ $data//tei:body/tei:p/text() ]]</p>
[% endlet %]
</article>
```

## Template Inheritance

Template inheritance allows you to create a hierarchy of templates where child templates can extend and customize parent templates. This is particularly useful for creating consistent layouts across multiple pages.

### How It Works

When a template extends another template:
- **Named templates** in the child replace corresponding blocks in the parent
- **Remaining content** is injected into the `content` block of the parent
- **Multiple levels** of inheritance are supported

### Example: Multi-level Template Hierarchy

Here's a complete example using the test application templates:

#### 1. Base Layout (`pages/page.html`)
```html
<div>
    <header>
        <nav>
            <ul>
                <li>page.html</li>
                [% block menu %][% endblock %]
            </ul>
        </nav>
    </header>
    <main>
        [% block content %][% endblock %]
    </main>
    [% include "pages/footer.html" %]
</div>
```

#### 2. Intermediate Template (`pages/base.html`)
```html
<article>
    ---json
    {
        "templating": {
            "extends": "pages/page.html"
        }
    }
    ---
    [% template menu %]
    <li>base.html</li>
    [% endtemplate %]
    <section>
        [% block content %][% endblock %]
        <p>This paragraph was imported from the parent template.</p>
    </section>
</article>
```

#### 3. Child Template with Additional Blocks
```html
---json
{
    "templating": {
        "extends": "pages/base.html",
        "use": ["pages/blocks.html"]
    }
}
---
[% template menu %]
<li>Extra menu item</li>
[% endtemplate %]

[% template copyright %]
<p>© e-editiones</p>
[% endtemplate %]

<div>
    <p>This is the main content of the page.</p>
    [% block foo %]
    <p>A block with default content not referenced by a template.</p>
    [% endblock %]
</div>
```

#### 4. Footer Template (`pages/footer.html`)
```html
<footer style="border-top: 1px solid #a0a0a0; margin-top: 1rem;">
    <p>Generated by [[$context?app]] running on [[system:get-product-name()]] v[[system:get-version()]].</p>
    [% block copyright %][% endblock %]
</footer>
```

#### 5. Additional Blocks (`pages/blocks.html`)
```html
<div>
    [% template menu %]
    <li>blocks.html</li>
    [% endtemplate %]
</div>
```

### Result

The final rendered output combines all templates:

```html
<div>
    <header>
        <nav>
            <ul>
                <li>page.html</li>
                <li>base.html</li>
                <li>Extra menu item</li>
                <li>blocks.html</li>
            </ul>
        </nav>
    </header>
    <main>
        <article>
            <section>
                <div>
                    <p>This is the main content of the page.</p>
                    <p>A block with default content not referenced by a template.</p>
                </div>
                <p>This paragraph was imported from the parent template.</p>
            </section>
        </article>
    </main>
    <footer style="border-top: 1px solid #a0a0a0; margin-top: 1rem;">
        <p>Generated by TEI Publisher running on eXist v6.2.0.</p>
        <p>© e-editiones</p>
    </footer>
</div>
```

### Key Concepts

- **`[% block name %]`** - Defines a named block that can be overridden
- **`[% template name %]`** - Provides content for a specific block
- **`[% include "path" %]`** - Includes another template file
- **`"use": ["path"]`** - Imports additional template files for block definitions
- **Frontmatter** - Configures inheritance and other templating options

### The `"use"` Directive

The `"use"` directive in frontmatter allows you to import additional template files that contain block definitions. This is particularly useful for:

- **Modular template components** - Reusable blocks across multiple templates
- **Organizing complex layouts** - Separating concerns into different files
- **Extending functionality** - Adding new blocks without modifying existing templates

#### How `"use"` Works

When you specify `"use": ["pages/blocks.html"]` in your frontmatter:

1. **Template Loading** - The specified template file is loaded and parsed
2. **Block Registration** - Any `[% template name %]` blocks in the imported file become available
3. **Content Injection** - These blocks can then be used to fill corresponding `[% block name %]` placeholders in the inheritance chain

#### Example: Using `pages/blocks.html`

In our example, `pages/blocks.html` contains:
```html
<div>
    [% template menu %]
    <li>blocks.html</li>
    [% endtemplate %]
</div>
```

When referenced with `"use": ["pages/blocks.html"]`, the `menu` template becomes available and gets injected into the menu block in the inheritance chain, resulting in an additional menu item.

#### Multiple `"use"` Files

You can specify multiple files in the `"use"` array:
```json
{
    "templating": {
        "extends": "pages/base.html",
        "use": [
            "pages/blocks.html",
            "pages/components.html",
            "pages/navigation.html"
        ]
    }
}
```

This allows you to build complex layouts by combining multiple modular template components.

### How context maps are merged

As the template inheritance examples may demonstrate, the library often has to merge different source maps into a single context map. This works as follows:

* properties with an __atomic value__ will overwrite earlier properties with the same key
* __maps__ will be processed recursively by merging the properties of each incoming into the outgoing map
    * if you would instead like to entirely replace a map, add a property `$replace` with value `true`
* __arrays__ are merged by appending the values of each incoming array with duplicates removed. Duplicates are determined as follows:
  * if the array contains atomic values only, they are compared using the `distinct-values` XPath function
  * if the values are maps and each map has an `id` property, they will be deduplicated using the value of this property.
  * if the values are maps and at least one does not have an `id` property, they will be serialized to JSON for deduplication

In the case of arrays of maps, we recommend that each map has an `id` property for correct deduplication.

## Testing

This project includes a integration test suite that validates the jinks-templates API functionality, as well as smoke tests for compiling and installing the application. The tests are automatically run on every push and pull request via GitHub Actions.

### Test Suite

This project includes a Cypress test suite for the Jinks Templates API. As well as smoke test using bats.

### Test Coverage

To execute the end-to-end test as small test app located in `test/app/` must be installed.

- **API Contract:** Basic endpoint accessibility and error handling (`api.cy.js`)
- **Template Processing:** HTML, CSS, and XQuery template rendering (`templateHtml.cy.js`, `templateCss.cy.js`, `templateXquery.cy.js`)
- **Security:** XSS, XQuery injection, path traversal, header spoofing (`api.security.cy.js`)

### Running Tests Locally

1. **Prerequisites:**
   - Node.js 22.0.0 or higher
   - Docker (for containerized testing)
   - Ant (for compiling `.xar` packages)

2. **Install dependencies:**
   ```bash
   npm install
   ```

3. **Deploy app** 
   - using the provided Dockerfile:
   ```shell
   docker build -t jinks-templates-test .
   docker run -dit -p 8080:8080 -p 8443:8443 jinks-templates-test
   ```
   - compile expath packages manually. From within the root of this repository:
   ```shell
   ant
   cd test/app
   ant
   ```
   Then proceed to install both `.xar` packages into your local exist-db responding on ports `8080` and `8443`

4. **Run tests:**
   ```sh
   npx cypress open
   # or
   npx cypress run
   ```

### GitHub Actions Workflow

The project includes a GitHub Actions workflow (`.github/workflows/test.yml`) that automatically:

1. **Builds the Docker image** containing eXist-db and the test application
2. **Starts the container** and waits for eXist-db to be ready
3. **Runs the test suite** against the running API
4. **Uploads test results** and coverage reports as artifacts
5. **Cleans up** containers and images

The workflow runs on:
- Every push
- Every pull request to `main` or `master` branches

## Release Procedure

This project uses [semantic-release](https://semantic-release.gitbook.io/) to automate versioning and publishing of releases on GitHub. The process is fully automated and based on commit messages following the [Conventional Commits](https://www.conventionalcommits.org/) specification.

### Branches

- **master**: Stable releases are published from this branch.
- **beta**: Pre-releases (e.g., `1.0.0-beta.1`) are published from this branch.

### How Releases Are Triggered

- Every push or pull request to `master` or `beta` triggers the test workflow.
- When the test workflow completes successfully, the release workflow runs.
- The release workflow analyzes commit messages to determine the next version:
  - **fix:** triggers a patch release (e.g., 1.0.1)
  - **feat:** triggers a minor release (e.g., 1.1.0)
  - **BREAKING CHANGE:** triggers a major release (e.g., 2.0.0)

### Pre-releases

- Commits pushed to the `beta` branch will create pre-releases (e.g., `1.0.0-beta.1`).


### Local Dry Run of Semantic Release

To simulate a release locally without publishing:

1. Obtain a GitHub token with `repo` permissions.
2. Run the following command in your project root (replace `your_token_here`):

   ```sh
   GH_TOKEN=your_token_here npx semantic-release --dry-run
   ```

This will show what semantic-release would do, without making any changes or publishing a release.

### Release Artifacts

- The build process creates a `.xar` package in the `build/` directory.
- This package is attached to each GitHub release automatically.

For more details, see the configuration in `.releaserc` and `.github/workflows/deploy.yml`.