xquery version "3.1";

module namespace tmpl="http://e-editiones.org/xquery/templates";

import module namespace cache="http://exist-db.org/xquery/cache" at "java:org.exist.xquery.modules.cache.CacheModule";

(:~
 : Thrown if the parser reaches the end of the input stream
 : while trying to find the end* marker for a block.
 :)
declare variable $tmpl:ERROR_EOF := xs:QName("tmpl:error-eof");
declare variable $tmpl:ERROR_SYNTAX := xs:QName("tmpl:error-syntax");
declare variable $tmpl:ERROR_INCLUDE := xs:QName("tmpl:error-include");
declare variable $tmpl:ERROR_EXTENDS := xs:QName("tmpl:error-extends");
declare variable $tmpl:ERROR_DYNAMIC := xs:QName("tmpl:error-dynamic");

declare variable $tmpl:CONFIG_PROPERTY := "templating";
declare variable $tmpl:CONFIG_IMPORTS := "ignoreImports";
declare variable $tmpl:CONFIG_PLAIN_TEXT := "plainText";
declare variable $tmpl:CONFIG_RESOLVER := "resolver";
declare variable $tmpl:CONFIG_DEBUG := "debug";
declare variable $tmpl:CONFIG_MODULES := "modules";
declare variable $tmpl:CONFIG_NAMESPACES := "namespaces";
declare variable $tmpl:CONFIG_EXTENDS := "extends";
declare variable $tmpl:CONFIG_USE := "use";
declare variable $tmpl:CONFIG_IGNORE_USE := "ignoreUse";
declare variable $tmpl:CONFIG_TEMPLATES := "templates";
declare variable $tmpl:CONFIG_REPLACE := "$replace";
(:~
 : The name of an eXist cache (cache module) in which tmpl:process keeps
 : compiled templates. Unset, nothing is cached.
 :)
declare variable $tmpl:CONFIG_CACHE := "cache";

(:~ The most compiled templates a cache created by tmpl:process holds. An app can create the cache itself to set its own limits. :)
declare variable $tmpl:CACHE_MAX_SIZE := 500;

(:~ This library's version, from its package descriptor; part of each cached template's key, so an upgrade compiles templates anew. :)
declare variable $tmpl:VERSION :=
    try {
        parse-xml(util:binary-to-string(repo:get-resource("http://tei-publisher.com/library/jinks-templates", "expath-pkg.xml")))/*/@version/string()
    } catch * {
        ""
    };

declare variable $tmpl:XML_MODE := map {
    "xml": true(),
    "block": map {
        "start": function($node as node()?) {
            let $firstChild := $node/node()[not(matches(., "^[\s\n]+$"))][1]
            return
                if (
                    $firstChild instance of element() and
                    not(
                        $firstChild instance of element(else) or
                        $firstChild instance of element(elif)
                    ) and
                    not($node/node()[not(matches(., "^[\s\n]+$"))][2])
                ) then
                    ()
                else
                    "&lt;t&gt;"
        },
        "end": function($node as node()?) {
            let $firstChild := $node/node()[not(matches(., "^[\s\n]+$"))][1]
            return
                if (
                    $firstChild instance of element() and
                    not(
                        $firstChild instance of element(else) or
                        $firstChild instance of element(elif)
                    ) and
                    not($node/node()[not(matches(., "^[\s\n]+$"))][2])
                ) then
                    ()
                else
                    "&lt;/t&gt;/node()"
        }
    },
    "enclose": map {
        "start": function($node as node()?) {
            let $preceding := $node/preceding-sibling::node()[not(matches(., "^[\s\n]+$"))][1]
            let $following := $node/following-sibling::node()[not(matches(., "^[\s\n]+$"))][1]
            return
                if (empty($preceding) and empty($following) and $node/parent::*[not(self::ast)]) then
                    ()
                else
                    "{"
        },
        "end": function($node as node()?) {
            let $preceding := $node/preceding-sibling::node()[not(matches(., "^[\s\n]+$"))][1]
            let $following := $node/following-sibling::node()[not(matches(., "^[\s\n]+$"))][1]
            return
                if (empty($preceding) and empty($following) and $node/parent::*[not(self::ast)]) then
                    ()
                else
                    "}"
        }
    },
    "text": function($text as xs:string) {
        replace($text, "\{", "{{") => replace("\}", "}}")
    }
};

declare variable $tmpl:TEXT_MODE := map {
    "xml": false(),
    "block": map {
        "start": function($node as node()?) { "``[" },
        "end": function($node as node()?) { "]``" }
    },
    "enclose": map {
        "start": function($node as node()?) { "`{" },
        "end": function($node as node()?) { "}`" }
    },
    "text": function($text as xs:string) {
        (: Escape string-constructor markers by emitting them via enclosed expressions. :)
        let $analyzed := analyze-string($text, '``\[|\]``|`\{|\}`')
        return
            string-join(
                for $part in $analyzed/*
                return
                    typeswitch($part)
                        case element(fn:match) return
                            switch($part/string())
                                case '``[' return '`{ "``[" }`'
                                case ']``' return '`{ "]``" }`'
                                case '`{' return '`{ "`{" }`'
                                case '}`' return '`{ "}`" }`'
                                default return
                                    $part/string()
                        default return
                            $part/string()
            )
    }
};

(:~
 : List of regular expressions used by the tokenizer
 :)
declare variable $tmpl:TOKEN_REGEX := [
    "\[%\s*(raw)\s*%\](.*?)\[%\s*(endraw)\s*%\]",
    "\[(#)(.*?)#\]",
    "\[%\s*(end\w+)\s*%\]",
    "\[%\s*(for)\s+(\$\w+)\s+in\s+(.+?)%\]",
    "\[%\s*(let)\s+(\$\w+)\s+=\s+(.+?)%\]",
    "\[%\s*(if)\s+(.+?)%\]",
    "\[%\s*(elif)\s+(.+?)%\]",
    "\[%\s*(else)\s*%\]",
    "\[%\s*(include)\s+(.+?)%\]",
    "\[%\s*(block)\s+(.+?)%\]",
    "\[%\s*(template!?)\s+(\S+?)(?:\s+(.*?))?%\]",
    '\[%\s*(import)\s+["''](.+?)["'']\s+as\s+["'']([\w\-_]+)["''](?:\s+at\s+["''](.+?)["''])?\s*%\]',
    '(\s*([\w:.-]+)\s*=\s*"(!)\[\[(.+?)\]\]")',
    "\[(\[)(.+?)\]\]"
];

(:~
 : Extract frontmatter
 :)
declare function tmpl:frontmatter($input as xs:string) {
    let $analyzed := analyze-string($input, "^(?:\s*.+?>)?\s*---(json|)\s*\n(.*?)\n\s*---.*$", "s")
    return
        if (count($analyzed//fn:group) = 2) then
            let $type := $analyzed//fn:group[@nr = 1]
            return
                if ($type = "json" or $type = "") then
                    let $text := $analyzed//fn:group[@nr = 2]/string()
                    return
                        parse-json($text)
                else
                    error($tmpl:ERROR_SYNTAX, "Unsupported frontmatter type " || $type)
        else
            map {}
};

(:~
 : Tokenize the input string. Returns a sequence of strings
 : and elements corresponding to the tokens found.
 :)
declare function tmpl:tokenize($input as xs:string) {
    let $regex := "(?:" || string-join($tmpl:TOKEN_REGEX, "|") || ")"
    (: Remove front matter :)
    let $input := replace($input, "^(\s*<.+?>)?\s*---(?:json|)\s*\n.*?\n\s*---(.*)$", "$1$2", "is")
    let $analyzed := analyze-string($input, $regex, "is")
    for $token in $analyzed/*
    return
        typeswitch($token)
            case element(fn:match) return
                let $type := $token/fn:group[1]
                let $token-string := $token/string()
                let $cond-attr := analyze-string($token-string, '^\s*([\w:.-]+)\s*=\s*"(!)\[\[(.+?)\]\]"$', "s")
                return
                    if (count($cond-attr//fn:group) = 3 and $cond-attr//fn:group[@nr = 2] = "!") then
                        <cond-attr
                            name="{$cond-attr//fn:group[@nr = 1] => normalize-space()}"
                            expr="{$cond-attr//fn:group[@nr = 3] => normalize-space()}"
                        />
                    else
                        switch($type)
                            case "endfor" return
                                <endfor/>
                            case "endlet" return
                                <endlet/>
                            case "endif" return
                                <endif/>
                            case "if" return
                                <if expr="{$token/fn:group[2] => normalize-space()}"/>
                            case "elif" return
                                <elif expr="{$token/fn:group[2] => normalize-space()}"/>
                            case "else" return
                                <else/>
                            case "for" return
                                <for var="{$token/fn:group[2] => normalize-space()}" expr="{$token/fn:group[3] => normalize-space()}"/>
                            case "let" return
                                <let var="{$token/fn:group[2] => normalize-space()}" expr="{$token/fn:group[3] => normalize-space()}"/>
                            case "include" return
                                <include target="{$token/fn:group[2] => normalize-space()}"/>
                            case "template" return
                                <template name="{$token/fn:group[2] => normalize-space()}"
                                    order="{$token/fn:group[3] => normalize-space()}"/>
                            case "template!" return
                                <template name="{$token/fn:group[2] => normalize-space()}" overwrite="true"/>
                            case "endtemplate" return
                                <endtemplate/>
                            case "block" return
                                <block name="{$token/fn:group[2] => normalize-space()}"/>
                            case "endblock" return
                                <endblock/>
                            case "#" return
                                ()
                            case "raw" return
                                <raw>{ $token/fn:group[2] => normalize-space() }</raw>
                            case "import" return
                                <import uri="{$token/fn:group[2] => normalize-space()}" as="{$token/fn:group[3] => normalize-space()}">
                                {
                                    if (count($token/fn:group) > 3) then
                                        attribute at {$token/fn:group[4] => normalize-space()}
                                    else
                                        ()
                                }
                                </import>
                            case "[" return
                                <value expr="{$token/fn:group[2] => normalize-space()}"/>
                            default return
                                <error>{$token}</error>
            default return
                $token/string()
};

(:~
 : Find the end* expression matching the starting token (if, for ...) given by $type.
 : Respect nested expressions.
 :)
declare %private function tmpl:lookahead($tokens as item()*, $type as xs:string, $nesting as xs:integer) {
    if (empty($tokens)) then
        error($tmpl:ERROR_EOF, "Missing end" || $type)
    else
        let $next := head($tokens)
        return ($next,
            if ($next instance of element()) then
                if (local-name($next) = $type) then
                    tmpl:lookahead(tail($tokens), $type, $nesting + 1)
                else if (local-name($next) = "end" || $type) then
                    if ($nesting = 1) then
                        ()
                    else
                        tmpl:lookahead(tail($tokens), $type, $nesting - 1)
                else
                    tmpl:lookahead(tail($tokens), $type, $nesting)
            else
                tmpl:lookahead(tail($tokens), $type, $nesting)
        )
};

(:~
 : Processes the token stream and returns an XML fragment representing the abstract
 : syntax tree of the template.
 :
 : @param $tokens the input token stream
 : @param $resolver a function to resolve references to external resources (for include)
 :)
declare function tmpl:parse($tokens as item()*, $resolver as function(*)?) {
    <ast>{tmpl:do-parse($tokens, $resolver)}</ast>
};

declare %private function tmpl:normalize-cond-attrs($nodes as item()*, $xml as xs:boolean) {
    let $normalized :=
        for $node in $nodes
        return
            typeswitch($node)
                case element(cond-attr) return
                    $node
                case element() return
                    element { node-name($node) } {
                        $node/@*,
                        tmpl:normalize-cond-attrs($node/node(), $xml)
                    }
                default return
                    $node
    return
        if ($xml) then
            tmpl:move-cond-attrs($normalized, (), (), $xml)
        else
            $normalized
};

declare %private function tmpl:move-cond-attrs($nodes as item()*, $output as item()*, $pending as element(cond-attr)*, $xml as xs:boolean) {
    if (empty($nodes)) then
        ($output, $pending)
    else
        let $next := head($nodes)
        let $tail := tail($nodes)
        return
            typeswitch($next)
                case element(cond-attr) return
                    tmpl:move-cond-attrs($tail, $output, ($pending, $next), $xml)
                case text() return
                    if (exists($pending) and contains($next, ">")) then
                        let $before := substring-before($next, ">")
                        let $after := substring-after($next, ">")
                        let $newOutput := (
                            $output,
                            if ($xml) then (
                                text { $before || ">" },
                                $pending
                            ) else (
                                text {
                                    if (matches($before, "/\s*$")) then
                                        replace($before, "\s*/\s*$", "")
                                    else
                                        $before
                                },
                                $pending,
                                text {
                                    if (matches($before, "/\s*$")) then
                                        "/>"
                                    else
                                        ">"
                                }
                            ),
                            if ($after != "") then text { $after } else ()
                        )
                        return
                            tmpl:move-cond-attrs($tail, $newOutput, (), $xml)
                    else
                        tmpl:move-cond-attrs($tail, ($output, $next), $pending, $xml)
                default return
                    tmpl:move-cond-attrs($tail, ($output, $next), $pending, $xml)
};

declare %private function tmpl:do-parse($tokens as item()*, $resolver as function(*)?) {
    if (empty($tokens)) then
        ()
    else
        let $next := head($tokens)
        return
            typeswitch ($next)
                case element(error) return
                    error($tmpl:ERROR_SYNTAX, $next/string())
                case element(for) return
                    let $body := tmpl:lookahead(tail($tokens), "for", 1)
                    let $tail := subsequence(tail($tokens), count($body) + 1)
                    return (
                        <for var="{$next/@var}" expr="{$next/@expr}">
                        {
                            tmpl:do-parse($body, $resolver)
                        }
                        </for>,
                        tmpl:do-parse($tail, $resolver)
                    )
                case element(let) return
                    let $body := tmpl:lookahead(tail($tokens), "let", 1)
                    let $tail := subsequence(tail($tokens), count($body) + 1)
                    return (
                        <let var="{$next/@var}" expr="{$next/@expr}">
                        {
                            tmpl:do-parse($body, $resolver)
                        }
                        </let>,
                        tmpl:do-parse($tail, $resolver)
                    )
                case element(if) return
                    let $body := tmpl:lookahead(tail($tokens), "if", 1)
                    let $tail := subsequence(tail($tokens), count($body) + 1)
                    return (
                        <if expr="{$next/@expr}">
                        {
                            tmpl:do-parse($body, $resolver)
                        }
                        </if>,
                        tmpl:do-parse($tail, $resolver)
                    )
                case element(elif) return
                    let $body := tmpl:lookahead(tail($tokens), "if", 1)
                    return (
                        <elif expr="{$next/@expr}">
                        {
                            tmpl:do-parse($body, $resolver)
                        }
                        </elif>
                    )
                case element(else) return
                    let $body := tmpl:lookahead(tail($tokens), "if", 1)
                    return (
                        <else>
                        {
                            tmpl:do-parse($body, $resolver)
                        }
                        </else>
                    )
                case element(template) return
                    let $body := tmpl:lookahead(tail($tokens), "template", 1)
                    let $tail := subsequence(tail($tokens), count($body) + 1)
                    return (
                        <template>
                        {
                            $next/@*,
                            tmpl:do-parse($body, $resolver)
                        }
                        </template>,
                        tmpl:do-parse($tail, $resolver)
                    )
                case element(block) return
                    let $body := tmpl:lookahead(tail($tokens), "block", 1)
                    let $tail := subsequence(tail($tokens), count($body) + 1)
                    return (
                        <block>
                        {
                            $next/@*,
                            tmpl:do-parse($body, $resolver)
                        }
                        </block>,
                        tmpl:do-parse($tail, $resolver)
                    )
                case element(raw) return
                    (
                        $next/node(),
                        tmpl:do-parse(tail($tokens), $resolver)
                    )
                case element(include) return (
                    (: check if we can do a static include :)
                    if (matches($next/@target, '^"[^"]*"$')) then
                        replace($next/@target, '^"([^"]*)"$', '$1') => tmpl:include-static($resolver)
                    else
                        $next,
                    tmpl:do-parse(tail($tokens), $resolver)
                )
                case element(import) return
                    ($next, tmpl:do-parse(tail($tokens), $resolver))
                case element(endfor) | element(endlet) | element(endif) | element(endblock) | element(endtemplate) | element(comment) return
                    ()
                default return
                    ($next, tmpl:do-parse(tail($tokens), $resolver))
};

(:~
 : Transform the AST into executable XQuery code, using the given configuration
 : and parameters.
 :
 : Depending on the desired output format (XML/HTML or text), $config should be either:
 : $tmpl:XML_MODE or $tmpl:TEXT_MODE.
 :)
declare function tmpl:generate($config as map(*), $ast as element(ast), $params as map(*), $modules as map(*)*,
    $namespaces as map(*)?,$resolver as function(*)?,  $incomingBlocks as element(template)*) {
    let $prolog := tmpl:prolog($ast, $modules, $namespaces, $resolver) => string-join('&#10;')
    let $body := $config?block?start(()) || string-join(tmpl:emit($config, $ast)) || $config?block?end(())
    let $code := string-join((tmpl:vars($params), $body), "&#10;")
    let $blocks :=
        <blocks xmlns="">
        {
            for $block in $incomingBlocks[not(@name = 'content')]
            return
                <template name="{$block/@name}">
                {
                    $block/@overwrite,
                    tmpl:escape-block($block/node())
                }
                </template>
        }
        </blocks>
    return
        (: start string template :)
        ``[
`{ $prolog }`

declare variable $local:blocks := `{ serialize($blocks) }`;

`{ $code }`
        ]``
        (: end string template :)
};

declare %private function tmpl:templating-param($params as map(*), $key as xs:string) {
    if (exists($params($tmpl:CONFIG_PROPERTY))) then
        $params($tmpl:CONFIG_PROPERTY)($key)
    else
        ()
};

declare %private function tmpl:escape-block($nodes as node()*) {
    for $node in $nodes
    return
        typeswitch ($node)
            case element() return
                element { node-name($node) } {
                    $node/@* except $node/@expr,
                    if ($node/@expr) then
                        attribute expr { $node/@expr => replace("([{}])", "$1$1") }
                    else
                        (),
                    tmpl:escape-block($node/node())
                }
            case text() return
                replace($node, "([{}])", "$1$1")
            default return
                $node
};

declare %private function tmpl:imported-modules($ast as element(ast), $resolver as function(*)?) {
    for $import in $ast/import
    return map {
        $import/@uri: map {
            "prefix": $import/@as,
            "at": $import/@at
        }
    }
};

declare %private function tmpl:prolog($ast as element(ast), $modules as map(*)*, $namespaces as map(*)*, $resolver as function(*)?) {
    if (exists($namespaces)) then
        map:for-each($namespaces, function($prefix, $uri) {
    ``[
    declare namespace `{$prefix}` = "`{$uri}`";]``
        })
    else
        (),
    if (exists($modules)) then
        map:for-each($modules, function($uri, $module) {
            let $location :=
                if ($module?at) then
                    if (starts-with($module?at, "xmldb:exist://")) then
                        $module?at
                    else if (exists($resolver)) then
                        let $resolved := $resolver($module?at)
                        return
                            if (exists($resolved)) then
                                $resolved?path
                            else
                                error($tmpl:ERROR_INCLUDE, "Cannot resolve module " || $module?at)
                    else
                        error($tmpl:ERROR_INCLUDE, "No resolver available. Cannot import module from " || $module?at)
                else
                    ()
            return
    ``[
    import module namespace `{$module?prefix}` = "`{$uri}`" `{if ($location) then 'at "' || $location || '"' else ()}`;]``
        })
    else
        ()
};

(:~
 : Recursively traverse AST nodes and generate XQuery code
 :)
declare %private function tmpl:emit($config as map(*), $nodes as item()*) {
    string-join(
        for $node in $nodes
        return
            typeswitch ($node)
                case element(if) return
                    $config?enclose?start($node)
                    || "if (" || $node/@expr || ") then&#10;"
                    || $config?block?start($node)
                    || tmpl:emit($config, $node/node())
                    || (if ($node/(else|elif)) then () else $config?block?end($node) || "&#10;else ()")
                    || $config?enclose?end($node)
                case element(elif) return
                    $config?block?end($node/..) ||
                    "&#10;else if (" || $node/@expr || ") then&#10;"
                    || $config?block?start($node)
                    || tmpl:emit($config, $node/node())
                    || (if ($node/(else|elif)) then () else $config?block?end($node) || "&#10;else ()")
                case element(else) return
                    $config?block?end($node/..) || " else&#10;" || $config?block?start($node)
                    || tmpl:emit($config, $node/node())
                    || $config?block?end($node)
                case element(for) return
                    $config?enclose?start($node)
                    || "for " || $node/@var || " in " || $node/@expr || " return&#10;"
                    || $config?block?start($node)
                    || tmpl:emit($config, $node/node())
                    || $config?block?end($node)
                    || $config?enclose?end($node)
                case element(let) return
                    $config?enclose?start($node)
                    || "let " || $node/@var || " := " || $node/@expr || " return&#10;"
                    || $config?block?start($node)
                    || tmpl:emit($config, $node/node())
                    || $config?block?end($node)
                    || $config?enclose?end($node)
                case element(include) return
                        $config?enclose?start($node)
                        || "tmpl:include(" || $node/@target || ", $_resolver, $context, "
                        || (if ($config?xml) then "false()" else "true()")
                        || ", $_modules, $_namespaces, $local:blocks/block)"
                        || $config?enclose?end($node)
                case element(content) return
                    $config?enclose?start($node)
                    || "tmpl:content("
                    || $config?block?start($node)
                    || tmpl:emit($config, $node/node())
                    || $config?block?end($node)
                    || (if ($node/@unwrap) then ", true()" else ", false()")
                    || ")"
                    || $config?enclose?end($node)
                case element(value) return
                    let $expr :=
                        if (matches($node/@expr, "^[^$][\w_-]+$")) then
                            "$" || $node/@expr
                        else
                            $node/@expr
                    return
                        $config?enclose?start($node)
                        || "tmpl:valueOf(" || $expr || ")"
                        || $config?enclose?end($node)
                case element(cond-attr) return
                    let $expr :=
                        if (matches($node/@expr, "^[^$][\w_-]+$")) then
                            "$" || $node/@expr
                        else
                            $node/@expr
                    let $attrName := $node/@name/string()
                    return
                        $config?enclose?start($node)
                        || "let $value := tmpl:valueOf(" || $expr || ") return "
                        || (
                            if ($config?xml) then
                                "if (count($value) > 1 or $value) then "
                                || "attribute " || $attrName || " { $value }"
                                || " else () "
                            else
                                "tmpl:conditional-attribute('" || $attrName || "', $value)"
                        )
                        || $config?enclose?end($node)
                case element(block) | element(import) return
                    ()
                case element() return
                    tmpl:emit($config, $node/node())
                default return
                    $config?text($node)
    )
};

declare function tmpl:valueOf($values as item()*) {
    for $value in $values
    return
        typeswitch ($value)
            case map(*) return
                serialize($value, map { "method": "json" })
            case array(*) return
                tmpl:valueOf($value?*)
            default return
                $value
};

declare function tmpl:conditional-attribute($name as xs:string, $value as item()*) as xs:string? {
    if (count($value) > 1 or $value) then
        " " || $name || '="' || tmpl:escape-attribute(string-join($value ! string(.), " ")) || '"'
    else
        ()
};

declare function tmpl:escape-attribute($value as xs:string) as xs:string {
    replace(
        replace(
            replace($value, "&amp;", "&amp;amp;"),
            '"',
            "&amp;quot;"
        ),
        "<",
        "&amp;lt;"
    )
};

(:~
 : Handle content blocks: remove the wrapping element if it is a <template> element or $unwrap is true
 :)
declare function tmpl:content($nodes as item()*, $unwrap as xs:boolean?) {
    typeswitch ($nodes)
        case element() return
            if (count($nodes) = 1 and ($unwrap or $nodes[1] instance of element(template))) then
                $nodes/node()
            else
                $nodes
        default return
            $nodes
};

(:~
 : Creates a let ... return prolog, mapping each key/value in $params
 : to a parameter named like the key.
 :)
declare %private function tmpl:vars($params as map(*)) {
    if (map:size($params) > 0) then
        map:for-each($params, function($key, $value) {
            if ($key = "$schema") then
                ()
            else
                ``[
let $`{$key}` := $context?`{$key}` ]``
        }) => string-join()
        || " return "
    else
        ()
};

(:~
 : Evaluate the passed in XQuery code.
 :)
declare function tmpl:eval($code as xs:string, $ast as element(), $context as map(*), $_resolver as function(*)?, $_modules as map(*)*, $_namespaces as map(*)?) {
    try {
        util:eval($code)
    } catch * {
        util:log("ERROR", $code),
        error($tmpl:ERROR_DYNAMIC, head(($err:description, "runtime error")), map {
            "description": $err:description,
            "code": $code,
            "ast": $ast
        })
    }
};

(:~
 : The context an extended template receives: "extends" and "use" are removed
 : from the templating params to avoid infinite recursion.
 :)
declare %private function tmpl:child-context($context as map(*)) as map(*) {
    map:merge((
        $context,
        if (map:contains($context, $tmpl:CONFIG_PROPERTY)) then
            map {
                "templating": map:remove(map:remove($context?($tmpl:CONFIG_PROPERTY), $tmpl:CONFIG_EXTENDS), $tmpl:CONFIG_USE)
            }
        else
            ()
    ), map { "duplicates": "use-last" })
};

(:~
 : The context tmpl:to-ast computes for $template, without parsing it: the
 : params merged with the frontmatter of the template and of each template it
 : extends, in the same order. A compiled template taken from the cache still
 : needs it, since it holds this call's params.
 :)
declare %private function tmpl:context($template as xs:string, $params as map(*), $config as map(*)) as map(*) {
    let $localContext := tmpl:frontmatter($template)
    let $extends := tmpl:templating-param($localContext, $tmpl:CONFIG_EXTENDS)
    let $modContext := tmpl:child-context(tmpl:merge-deep(($params, $localContext)))
    return
        if ($extends) then
            tmpl:context($config?resolver($extends)?content, $modContext, $config)
        else
            $modContext
};

(:~
 : Parses a template into an abstract syntax tree (AST), recursively merging extended templates and blocks.
 :)
declare function tmpl:to-ast($template as xs:string, $params as map(*), $config as map(*), $blocks as element(template)*) {
    let $localContext := tmpl:frontmatter($template)
    let $extends := tmpl:templating-param($localContext, $tmpl:CONFIG_EXTENDS)
    let $context := tmpl:merge-deep(($params, $localContext))
    let $incomingBlocks := (
        $blocks,
        tmpl:external-blocks($config, $context, $config?resolver)
    )
    let $modContext := tmpl:child-context($context)
    let $ast := tmpl:tokenize($template) => tmpl:parse($config?resolver)
    let $ast := <ast>{ tmpl:normalize-cond-attrs($ast/node(), not($config?plainText)) }</ast>
    let $ast := tmpl:expand-blocks($ast, $incomingBlocks)
    return
        if ($extends) then
            let $contentBlock :=
                <template name="content">
                {
                    if ($localContext?($tmpl:CONFIG_PROPERTY)?strip-root) then
                        attribute { "unwrap" } { "true" }
                    else
                        (),
                    tmpl:get-content($ast)
                }
                </template>
            return
                if (empty($config?resolver)) then
                    error($tmpl:ERROR_EXTENDS, "Extends is not available in this templating context")
                else
                    let $baseTemplate := $config?resolver($extends)
                    return
                        if (exists($baseTemplate)) then
                            tmpl:to-ast($baseTemplate?content, $modContext, $config, ($incomingBlocks except $incomingBlocks[@name = 'content'], $ast//template, $contentBlock))
                        else
                            error($tmpl:ERROR_EXTENDS, "Extended template " || $extends || " not found")
        else
            map {
                "ast": tmpl:expand-default-blocks($ast),
                "context": $modContext,
                "blocks": $blocks
            }
};

(:~
 : Resolve blocks in the AST, appending the content of matching templates.
 :)
declare %private function tmpl:expand-blocks($ast as node()*, $blocks as element(template)*) {
    for $node in $ast
    return
        typeswitch($node)
            case element(block) return
                if ($node/@append) then
                    $node
                else
                    let $blocks := $blocks[@name = $node/@name]
                    return
                        if ($blocks) then
                            let $selectedBlocks :=
                                if ($blocks[@overwrite='true']) then
                                    $blocks[@overwrite='true']
                                else
                                    $blocks
                            let $orderedBlocks :=
                                for $block in $selectedBlocks[@order != '']
                                order by xs:integer($block/@order) ascending empty greatest
                                return
                                    $block
                            for $block in ($orderedBlocks, reverse($selectedBlocks[@order = '' or not(@order)]))
                            return
                                if ($block/@unwrap) then
                                    <content unwrap="true">{ $block/node() }</content>
                                else if ($block/@name = 'content') then
                                    <content>{ $block/node() }</content>
                                else
                                    $block/node()
                        else
                            (: Defer until later :)
                            $node
            case element() return
                element { node-name($node) } {
                    $node/@*,
                    tmpl:expand-blocks($node/node(), $blocks)
                }
            default return
                $node
};

declare %private function tmpl:expand-default-blocks($ast as node()*) {
    for $node in $ast
    return
        typeswitch($node)
            case element(block) return
                $node/node()
            case element() return
                element { node-name($node) } {
                    $node/@*,
                    tmpl:expand-default-blocks($node/node())
                }
            default return
                $node
};

declare %private function tmpl:get-content($ast as node()*) {
    for $node in $ast
    return
        typeswitch($node)
            case element(template) return
                ()
            case element(ast) return
                tmpl:get-content($node/node())
            case element() return
                element { node-name($node) } {
                    $node/@*,
                    tmpl:get-content($node/node())
                }
            default return
                $node
};

declare %private function tmpl:external-blocks($config as map(*), $params as map(*), $resolver as function(*)?) {
    if (not($config?($tmpl:CONFIG_IGNORE_USE)) and map:contains($params, $tmpl:CONFIG_PROPERTY)) then
        for $file in $params?($tmpl:CONFIG_PROPERTY)?($tmpl:CONFIG_USE)?*
        let $template := $resolver($file)
        return
            if (exists($template)) then
                let $externalBlocks := (tmpl:tokenize($template?content) => tmpl:parse($resolver))//template
                return $externalBlocks
            else
                error($tmpl:ERROR_INCLUDE, "Included template " || $file || " not found")
    else
        (),
    if (map:contains($config, $tmpl:CONFIG_TEMPLATES)) then
        let $templates := $config?($tmpl:CONFIG_TEMPLATES)
        return
            if ($templates instance of map(*)) then
                map:for-each($config?($tmpl:CONFIG_TEMPLATES), function($key, $expr) {
                    <template name="{$key}">{$expr}</template>
                })
            else
                ()
    else
        ()
};

declare function tmpl:process($template as xs:string, $params as map(*), $config as map(*)) {
    tmpl:process($template, $params, $config, ())
};

(:~
 : Process a template. With $tmpl:CONFIG_CACHE set to a cache name, the
 : compiled template is kept in that eXist cache: a later call with the same
 : template, the same param names (values may differ) and the same config
 : evaluates the stored code instead of parsing and generating it again, as
 : long as none of the templates it extends or includes has changed.
 :)
declare function tmpl:process($template as xs:string, $params as map(*), $config as map(*), $blocks as element(template)*) {
    let $cacheName := if ($config?($tmpl:CONFIG_DEBUG)) then () else $config?($tmpl:CONFIG_CACHE)
    let $key := if ($cacheName) then tmpl:cache-key($template, $params, $config, $blocks) else ()
    let $compiled :=
        if ($key) then
            let $created := cache:create($cacheName, map { "maximumSize": $tmpl:CACHE_MAX_SIZE })
            let $entry := cache:get($cacheName, $key)
            return
                if ($entry instance of map(*) and tmpl:dependencies-unchanged($entry?dependencies, $config?resolver)) then
                    $entry
                else
                    ()
        else
            ()
    return
        if (exists($compiled)) then
            tmpl:eval($compiled?code, $compiled?ast, tmpl:context($template, $params, $config), $config?resolver,
                $compiled?modules, $compiled?namespaces)
        else
            tmpl:compile($template, $params, $config, $blocks, $cacheName, $key)
};

(:~
 : What the generated code depends on, besides the templates it extends or
 : includes: the template, the names (not the values) of the params, the
 : params' templating section, the blocks, the config and this library's
 : version. Empty if any of them can't be serialized; then nothing is cached.
 :)
declare %private function tmpl:cache-key($template as xs:string, $params as map(*), $config as map(*),
        $blocks as element(template)*) as xs:string? {
    try {
        util:hash(string-join((
            $tmpl:VERSION,
            $template,
            string-join(sort(map:keys($params)), ","),
            serialize($params?($tmpl:CONFIG_PROPERTY), map { "method": "json" }),
            serialize($blocks),
            serialize(map:remove($config, ($tmpl:CONFIG_RESOLVER, $tmpl:CONFIG_DEBUG, $tmpl:CONFIG_CACHE)), map { "method": "json" })
        ), "&#10;&#31;&#10;"), "sha-256")
    } catch * {
        ()
    }
};

(:~
 : True if each template a compiled template depends on still has the content
 : it was compiled from. The map comes from the cache, so it is read with the
 : lookup operator: calling a cached map as a function ($dependencies($path))
 : fails in eXist when another request uses it at the same time.
 :)
declare %private function tmpl:dependencies-unchanged($dependencies as map(*)?, $resolver as function(*)?) as xs:boolean {
    exists($dependencies) and
        (every $path in map:keys($dependencies) satisfies $dependencies?($path) eq tmpl:content-hash($resolver($path)))
};

declare %private function tmpl:content-hash($resolved as map(*)?) as xs:string {
    if (exists($resolved)) then util:hash(string($resolved?content), "sha-1") else ""
};

(:~
 : Parse, generate and evaluate a template. With $key, the resolver records
 : each template it resolves along the way, in a cache of its own, and the
 : compiled template is stored under $key with the content hash of each of them.
 :)
declare %private function tmpl:compile($template as xs:string, $params as map(*), $config as map(*),
        $blocks as element(template)*, $cacheName as xs:string?, $key as xs:string?) {
    let $recorder := if ($key) then "tmpl-dependencies-" || util:uuid() else ()
    let $compileConfig :=
        if ($recorder) then
            map:put($config, $tmpl:CONFIG_RESOLVER, function($path as xs:string) {
                let $resolved := $config?resolver($path)
                let $record := cache:put($recorder, $path, tmpl:content-hash($resolved))
                return $resolved
            })
        else
            $config
    let $ast := tmpl:to-ast($template, $params, $compileConfig, $blocks)
    let $modules := map:merge((
        $config?modules,
        if (not($config?($tmpl:CONFIG_IMPORTS)) and exists($ast?context?($tmpl:CONFIG_PROPERTY))) then
            $ast?context?($tmpl:CONFIG_PROPERTY)?modules
        else
            (),
        tmpl:imported-modules($ast?ast, $compileConfig?resolver)
    ), map { "duplicates": "use-last" })
    let $namespaces := map:merge((
        $config?namespaces,
        if (exists($ast?context?($tmpl:CONFIG_PROPERTY))) then
            $ast?context?($tmpl:CONFIG_PROPERTY)?namespaces
        else
            ()
    ), map { "duplicates": "use-last" })
    let $mode := if ($config?plainText) then $tmpl:TEXT_MODE else $tmpl:XML_MODE
    let $code := tmpl:generate($mode, $ast?ast, $ast?context, $modules, $namespaces, $compileConfig?resolver, $ast?blocks)
    let $store :=
        if ($key) then
            let $dependencies := map:merge(cache:keys($recorder) ! map:entry(., cache:get($recorder, .)))
            let $done := cache:destroy($recorder)
            return cache:put($cacheName, $key, map {
                "code": $code, "ast": $ast?ast, "modules": $modules, "namespaces": $namespaces, "dependencies": $dependencies
            })
        else
            ()
    let $result := tmpl:eval($code, $ast?ast, $ast?context, $config?resolver, $modules, $namespaces)
    return
        if ($config?debug) then
            map {
                "ast": $ast?ast,
                "xquery": $code,
                "result":
                    if (not($config?plainText)) then
                        serialize($result, map { "indent": true() })
                    else
                        $result
            }
        else
            $result
};

(:~
 : Get the distinct values in a sequence, paying special attention to sequences of maps:
 :
 : * if all maps have an "id" key, the values are deduplicated by this key
 : * otherwise, the values are serialized and deduplicated by their JSON representation
 :)
declare %private function tmpl:distinct-values($values) {
    typeswitch ($values)
        case map(*)+ return
            if (every $value in $values satisfies map:contains($value, "id")) then
                let $uniqueIds := distinct-values($values ! map:get(.,"id"))
                let $byId := map:merge(for $value in $values return map:entry(map:get($value, "id"), $value), map { "duplicates": "use-last" })
                for $id in $uniqueIds
                return
                    $byId($id)
            else
                let $jsonValues :=
                    for $value in $values
                    return
                        serialize($value, map { "method": "json", "indent": false() })
                for $value in distinct-values($jsonValues)
                return
                    parse-json($value)
        default return
            distinct-values($values)
};

(:~
 : Deep merge a sequence of maps: maps are merged recursively, arrays are merged by taking the distinct values.
 :)
declare function tmpl:merge-deep($maps as map(*)*) {
    tmpl:merge-deep($maps, ())
};

declare %private function tmpl:merge-deep($maps as map(*)*, $overwriteKeys as xs:string*) {
    if (count($maps) < 2) then
        $maps
    else
        map:merge(
            for $key in distinct-values($maps ! map:keys(.)[. != $tmpl:CONFIG_REPLACE])
            let $mapsWithKey := filter($maps, function($map) { map:contains($map, $key) })
            let $newVal :=
                if ($key = $overwriteKeys) then
                    (: Overwrite the key with the value from the last map :)
                    $mapsWithKey[last()]($key)
                else if ($mapsWithKey[1]($key) instance of map(*)) then
                    let $replace := $mapsWithKey[last()]($key)($tmpl:CONFIG_REPLACE)
                    return
                        if (exists($replace) and not($replace instance of array(*))) then
                            (: If $replace is a boolean, return the last map, but remove the $replace key :)
                            map:remove($mapsWithKey[last()]($key), $tmpl:CONFIG_REPLACE)
                        else
                            (: If $replace is an array, merge the maps, but replace the keys listed in $replace with
                               the key value from the last map :)
                            tmpl:merge-deep($mapsWithKey ! .($key), $replace?*)
                else if ($mapsWithKey[1]($key) instance of array(*)) then
                    let $values := $mapsWithKey ! .($key)?*
                    return
                        array { tmpl:distinct-values($values) }
                else
                    (: Atomic values: use the value from the last map :)
                    $mapsWithKey[last()]($key)
            return
                map:entry($key, $newVal),
        map { "duplicates": "use-last" })
};

declare function tmpl:include-static($path as xs:string, $resolver as function(*)?) {
    if (empty($resolver)) then
        error($tmpl:ERROR_INCLUDE, "Include is not available in this templating context")
    else
        let $template := $resolver($path)
        return
            if (exists($template)) then
                tmpl:tokenize($template?content) => tmpl:parse($resolver)
            else
                error($tmpl:ERROR_INCLUDE, "Included template " || $path || " not found")
};

declare function tmpl:include($path as xs:string, $resolver as function(*)?, $params as map(*),
    $plainText as xs:boolean?, $modules as map(*)*, $namespaces as map(*)?, $blocks as element()*) {
    if (empty($resolver)) then
        error($tmpl:ERROR_INCLUDE, "Include is not available in this templating context")
    else
        let $template := $resolver($path)
        return
            if (exists($template)) then
                let $result := tmpl:process($template?content, $params, map {
                    $tmpl:CONFIG_PLAIN_TEXT: $plainText,
                    $tmpl:CONFIG_RESOLVER: $resolver,
                    $tmpl:CONFIG_DEBUG: false(),
                    $tmpl:CONFIG_MODULES: $modules,
                    $tmpl:CONFIG_NAMESPACES: $namespaces
                }, $blocks)
                return
                    if ($result instance of map(*) and $result?error) then
                        error($tmpl:ERROR_INCLUDE, $result?error)
                    else
                        $result
            else
                error($tmpl:ERROR_INCLUDE, "Included template " || $path || " not found")
};
