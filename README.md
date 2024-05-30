# A Templating Library in Plain XQuery

eXist's HTML templating is only usable for HTML, but for app generation tasks we needed a library, which is able to process both, XML/HTML and plain text files. The module was inspired by other templating languages like [nunjucks](https://mozilla.github.io/nunjucks/) or *jsx*, but uses the full power of XPath for expressions. It was also designed to be backwards-compatible with the simpler templating syntax TEI Publisher uses within ODD, further extending the possibilities available within the `pb:template` element in ODD.

Instead of being entirely based on regular expressions, the templating module implements a parser generating an abstract syntax tree (AST) in XML. The AST is then compiled into XQuery code, which - when executed - produces the final output.

## Expressions

The template syntax is similar to [nunjucks](https://mozilla.github.io/nunjucks/) or [jinja](https://jinja.palletsprojects.com/en/3.1.x/templates/), but uses the host language for all expressions, therefore giving users the full power of XPath/XQuery.

The templating is passed a context map, which should containing all the information necessary for processing the template expressions. Each top-level property in the context map is made available as an XQuery variable. So if you have a context map like

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

you can use a value expression `[[$title]]` to output the title. And to insert the content font, use `[[$theme?fonts?content]]`.

Supported template expressions are:

| Expression | Description |
| -------- | ------- |
| `[[ expr ]]` | Insert result of evaluating `expr` |
| `[% if expr %] … [% endif %]` | Conditional evaluation of block |
| `… [% elsif expr %] …` | *else if* block after *if* |
| `… [% else %] … [% endif %]` | *else* block after *if* or *else if* |
| `[% for $var in expr %] … [% endfor %]` | Loop `$var` over sequence returned by `expr` |
| `[% include expr %]` | Include a partial. `expr` should resolve to relative path. |
| `[% extends expr %]` | Extend a base template: contents of child template passed to base template in variable `$content`. Named blocks in child overwrite blocks in base. |
| `[% block name %] … [% endblock %]` | Defines a named block or overwrites corresponding block in base template. |
| `[# … #]` | Single or multi-line comment: content will be discarded |

`expr` must be a valid XPath expression.

For some real pages built with jinks-templates, check the main [jinks app manager](https://github.com/eeditiones/jinks/tree/main/pages). This app also includes a playground and demo for jinks-templates.

## Output Modes

The library supports two modes: **XML/HTML** and **plain text**. They differ in the XQuery code templates are compiled into. While the first will always return XML – and fails if the result is not well-formed, the second uses XQuery string templates.

## Use in XQuery

The library exposes one main function, `tmpl:process`, which takes 4 arguments:

1. the template to process as a string
2. the context providing the information to be passed to templating expressions
3. a boolean flag to indicate the mode: if true, output will be plain text, XML otherwise
4. an optional resolver function to be used when looking up included files

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
    tmpl:process($input, $context, false(), ())
```

In the example above, the input is constructed as XML, but serialized into a string for the call to `tmpl:process`. The context map contains a single property, which will become available as variable `$title` within template expressions.

The final argument is needed if you would like to use `[% include %]`, `[% extends %]` or `[% import %]` in your templates. It should point to a function with one parameter: the relative path to the resource, and should return a map with two fields:

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
return
    tmpl:process($input, $context, false(), local:resolver#1)
```