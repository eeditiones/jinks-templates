xquery version "3.1";

module namespace tmpl="http://e-editiones.org/xquery/templates";

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
declare variable $tmpl:CONFIG_BLOCKS := "blocks";
declare variable $tmpl:CONFIG_EXTENDS := "extends";

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
                    )
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
                    )
                ) then
                    ()
                else
                    "&lt;/t&gt;/node()"
        }
    },
    "enclose": map {
        "start": function($node as node()?) {
            let $preceding := $node/preceding-sibling::node()[not(matches(., "^[\s\n]+$"))][1]
            return
                if (empty($preceding) and $node/parent::*[not(self::ast)]) then
                    ()
                else
                    "{"
        },
        "end": function($node as node()?) {
            let $preceding := $node/preceding-sibling::node()[not(matches(., "^[\s\n]+$"))][1]
            return
                if (empty($preceding) and $node/parent::*[not(self::ast)]) then
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
        $text
    }
};

(:~
 : List of regular expressions used by the tokenizer
 :)
declare variable $tmpl:TOKEN_REGEX := [
    "\[%\s*(end\w+)\s*%\]",
    "\[%\s*(for)\s+(\$\w+)\s+in\s+(.+?)%\]",
    "\[%\s*(let)\s+(\$\w+)\s+=\s+(.+?)%\]",
    "\[%\s*(if)\s+(.+?)%\]",
    "\[%\s*(elif)\s+(.+?)%\]",
    "\[%\s*(else)\s*%\]",
    "\[%\s*(include)\s+(.+?)%\]",
    "\[%\s*(extends)\s+(.+?)%\]",
    "\[%\s*(block)\s+(.+?)%\]",
    '\[%\s*(import)\s+["''](.+?)["'']\s+as\s+["'']([\w\-_]+)["''](?:\s+at\s+["''](.+?)["''])?\s*%\]',
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
            ()
};

(:~
 : Tokenize the input string. Returns a sequence of strings
 : and elements corresponding to the tokens found.
 :)
declare function tmpl:tokenize($input as xs:string) {
    let $regex := "(?:" || string-join($tmpl:TOKEN_REGEX, "|") || ")"
    (: First remove comments :)
    let $input := replace($input, "\[(#)(.*?)#\]", "", "is")
    (: Remove front matter :)
    let $input := replace($input, "^(\s*<.+?>)?\s*---(?:json|)\s*\n.*?\n\s*---(.*)$", "$1$2", "is")
    let $analyzed := analyze-string($input, $regex, "is")
    for $token in $analyzed/*
    return
        typeswitch($token)
            case element(fn:match) return
                let $type := $token/fn:group[1]
                return
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
                    case "extends" return
                        <extends source="{$token/fn:group[2] => normalize-space()}"/>
                    case "block" return
                        <block name="{$token/fn:group[2] => normalize-space()}"/>
                    case "endblock" return
                        <endblock/>
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
declare function tmpl:parse($tokens as item()*) {
    <ast>{tmpl:do-parse($tokens)}</ast>
};

declare %private function tmpl:do-parse($tokens as item()*) {
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
                            tmpl:do-parse($body)
                        }
                        </for>,
                        tmpl:do-parse($tail)
                    )
                case element(let) return
                    let $body := tmpl:lookahead(tail($tokens), "let", 1)
                    let $tail := subsequence(tail($tokens), count($body) + 1)
                    return (
                        <let var="{$next/@var}" expr="{$next/@expr}">
                        {
                            tmpl:do-parse($body)
                        }
                        </let>,
                        tmpl:do-parse($tail)
                    )
                case element(if) return
                    let $body := tmpl:lookahead(tail($tokens), "if", 1)
                    let $tail := subsequence(tail($tokens), count($body) + 1)
                    return (
                        <if expr="{$next/@expr}">
                        {
                            tmpl:do-parse($body)
                        }
                        </if>,
                        tmpl:do-parse($tail)
                    )
                case element(elif) return
                    let $body := tmpl:lookahead(tail($tokens), "if", 1)
                    return (
                        <elif expr="{$next/@expr}">
                        {
                            tmpl:do-parse($body)
                        }
                        </elif>
                    )
                case element(else) return
                    let $body := tmpl:lookahead(tail($tokens), "if", 1)
                    return (
                        <else>
                        {
                            tmpl:do-parse($body)
                        }
                        </else>
                    )
                case element(block) return
                    let $body := tmpl:lookahead(tail($tokens), "block", 1)
                    let $tail := subsequence(tail($tokens), count($body) + 1)
                    return (
                        <block name="{$next/@name}">
                        {
                            tmpl:do-parse($body)
                        }
                        </block>,
                        tmpl:do-parse($tail)
                    )
                case element(include) | element(extends) | element(import) return
                    ($next, tmpl:do-parse(tail($tokens)))
                case element(endfor) | element(endlet) | element(endif) | element(endblock) | element(comment) return
                    ()
                default return
                    ($next, tmpl:do-parse(tail($tokens)))
};

(:~
 : Transform the AST into executable XQuery code, using the given configuration
 : and parameters.
 :
 : Depending on the desired output format (XML/HTML or text), $config should be either:
 : $tmpl:XML_MODE or $tmpl:TEXT_MODE.
 :)
declare function tmpl:generate($config as map(*), $ast as element(ast), $params as map(*), $modules as map(*)*, 
    $namespaces as map(*)?, $incomingBlocks as element()?, $extends as xs:string?, $resolver as function(*)?) {
    let $prolog := tmpl:prolog($ast, $modules, $namespaces, $resolver) => string-join('&#10;')
    let $body := $config?block?start(()) || string-join(tmpl:emit($config, $ast)) || $config?block?end(())
    let $code := string-join((tmpl:vars($params), $body), "&#10;")
    let $blocks :=
        <blocks xmlns="">
        {
            for $block in ($ast//block, $incomingBlocks/block)
            return
                <block name="{$block/@name}">
                {
                    tmpl:escape-block($block/node())
                }
                </block>
        }
        </blocks>
    let $extends :=
        if ($ast//extends/@source) then
            $ast//extends/@source
        else if ($extends) then
            '"' || $extends || '"'
        else
            ()
    return
        (: if template extends another, output call to tmpl:extends :)
        if ($extends) then
(: start string template :)
            ``[
`{ $prolog }`

declare variable $local:blocks :=
    `{ serialize($blocks) }`
;

declare function local:content($context as map(*), $_resolver as function(*), $_modules as map(*)?, $_namespaces as map(*)?) {
    `{$code}`
};
            
tmpl:extends(`{$extends}`, local:content#4, $context, $_resolver, 
    `{if ($config?xml) then 'false()' else 'true()'}`, $_modules, $_namespaces, $local:blocks)]``
(: end string template :)

        (: otherwise just output the code :)
        else
(: start string template :)
            ``[
`{ $prolog }`

declare variable $local:blocks :=
    `{serialize($blocks)}`
;

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
                    || ", $_modules, $_namespaces, $local:blocks)"
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

(:~
 : Creates a let ... return prolog, mapping each key/value in $params
 : to a parameter named like the key.
 :)
declare %private function tmpl:vars($params as map(*)) {
    if (map:size($params) > 0) then
        map:for-each($params, function($key, $value) {
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
 : Compile and execute the given template. Convenience method which combines
 : tokenize, parse, generate and eval.
 :)
declare function tmpl:process($template as xs:string, $params as map(*), $config as map(*)) {
    let $ast := tmpl:tokenize($template) => tmpl:parse()
    let $mode := if ($config?plainText) then $tmpl:TEXT_MODE else $tmpl:XML_MODE
    let $params := tmpl:merge-deep(($params, tmpl:frontmatter($template)))
    let $extends := tmpl:templating-param($params, $tmpl:CONFIG_EXTENDS)
    (: Remove "extends" from templating params to avoid infinite recursion :)
    let $params := map:merge((
        $params,
        if (map:contains($params, $tmpl:CONFIG_PROPERTY)) then
            map {
                "templating": map:remove($params?($tmpl:CONFIG_PROPERTY), $tmpl:CONFIG_EXTENDS)
            }
        else
            ()
    ))
    let $modules := map:merge((
        $config?modules,
        if (not($config?($tmpl:CONFIG_IMPORTS)) and exists($params?($tmpl:CONFIG_PROPERTY))) then
            $params?($tmpl:CONFIG_PROPERTY)?modules
        else
            (),
        tmpl:imported-modules($ast, $config?resolver)
    ))
    let $namespaces := map:merge((
        $config?namespaces,
        if (exists($params?($tmpl:CONFIG_PROPERTY))) then
            $params?($tmpl:CONFIG_PROPERTY)?namespaces
        else
            ()
    ))
    let $modifiedAst := 
        if (map:contains($config, $tmpl:CONFIG_BLOCKS)) then
            tmpl:replace-blocks($ast, $config?($tmpl:CONFIG_BLOCKS))
        else
            $ast
    let $code := tmpl:generate($mode, $modifiedAst, $params, $modules, $namespaces, 
        $config?($tmpl:CONFIG_BLOCKS), $extends, $config?resolver)
    let $result := tmpl:eval($code, $modifiedAst, $params, $config?resolver, $modules, $namespaces)
    return
        if ($config?debug) then
            map {
                "ast": $ast,
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
 : Find distinct values in a sequence which may contain maps or atomic values. 
 :)
declare %private function tmpl:distinct-values($values) {
    typeswitch ($values)
        case map(*)+ return
            let $jsonValues := 
                map:merge(
                    for $value in $values 
                    return map {
                        serialize($value, map { "method": "json", "indent": false() }): $value
                    }
                )
            for $json in distinct-values(map:keys($jsonValues))
            return
                $jsonValues($json)
        default return
            distinct-values($values)
};

declare function tmpl:merge-deep($maps as map(*)*) {
    if (count($maps) < 2) then
        $maps
    else
        map:merge(
            for $key in distinct-values($maps ! map:keys(.))
            let $mapsWithKey := filter($maps, function($map) { map:contains($map, $key) })
            let $newVal :=
                if ($mapsWithKey[1]($key) instance of map(*)) then
                    tmpl:merge-deep($mapsWithKey ! .($key))
                else if ($mapsWithKey[1]($key) instance of array(*)) then
                    let $values := $mapsWithKey ! .($key)?*
                    return
                        array { tmpl:distinct-values($values) }
                else
                    $mapsWithKey[last()]($key)
            return
                map:entry($key, $newVal)
        )
};

declare function tmpl:include($path as xs:string, $resolver as function(*)?, $params as map(*), 
    $plainText as xs:boolean?, $modules as map(*)*, $namespaces as map(*)?, $blocks as element()) {
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
                    $tmpl:CONFIG_NAMESPACES: $namespaces,
                    $tmpl:CONFIG_BLOCKS: $blocks
                })
                return
                    if ($result instance of map(*) and $result?error) then
                        error($tmpl:ERROR_INCLUDE, $result?error)
                    else
                        $result
            else
                error($tmpl:ERROR_INCLUDE, "Included template " || $path || " not found")
};

(:~
 : Helper function called at runtime: 
 : 
 : * load and parse the base template specified by $path
 : * call $contentFunc to set variable $content
 : * replace all named blocks in ast of base template with corresponding blocks from child
 : given in $blocks
 :)
declare function tmpl:extends($path as xs:string, $contentFunc as function(*), $params as map(*), 
    $resolver as function(*)?, $plainText as xs:boolean?, $modules as map(*)*, 
    $namespaces as map(*)?, $blocks as element()) {
    if (empty($resolver)) then
        error($tmpl:ERROR_EXTENDS, "Extends is not available in this templating context")
    else
        let $template := $resolver($path)
        return
            if (exists($template)) then
                let $content := $contentFunc($params, $resolver, $modules, $namespaces)
                let $params := map:merge((
                    $params,
                    map {
                        "content": $content
                    }
                ))
                return
                    tmpl:process-blocks($template?content, $params, $plainText, $resolver, $modules, $namespaces, $blocks)
            else
                error($tmpl:ERROR_EXTENDS, "Extended template " || $path || " not found")
};

declare %private function tmpl:process-blocks($template as xs:string, $params as map(*), $plainText as xs:boolean?,
    $resolver as function(*), $modules as map(*)*, $namespaces as map(*)?, $blocks as element()) {
    (: parse the extended template :)
    let $ast := tmpl:tokenize($template) => tmpl:parse()
    (: replace blocks in template with corresponding blocks of child :)
    let $modifiedAst := tmpl:replace-blocks($ast, $blocks)
    let $modules := map:merge((
        $modules,
        if (exists($params?($tmpl:CONFIG_PROPERTY))) then
            $params?($tmpl:CONFIG_PROPERTY)?modules
        else
            (),
        tmpl:imported-modules($modifiedAst, $resolver)
    ))
    let $mode := if ($plainText) then $tmpl:TEXT_MODE else $tmpl:XML_MODE
    let $code := tmpl:generate($mode, $modifiedAst, $params, $modules, $namespaces, $blocks, (), $resolver)
    return
        try {
            tmpl:eval($code, $ast, $params, $resolver, $modules, $namespaces)
        } catch * {
            error($tmpl:ERROR_EXTENDS, $err:description, $err:value)
        }
};

declare %private function tmpl:replace-blocks($ast as node()*, $blocks as element()) {
    for $node in $ast
    return
        typeswitch($node)
            case element(block) return
                if ($blocks/block[@name = $node/@name]) then (
                    try {
                        $blocks/block[@name = $node/@name]/node()
                    } catch * {
                        $blocks/block[@name = $node/@name]/node()
                    }
                ) else
                    $node/node()
            case element() return
                element { node-name($node) } {
                    $node/@*,
                    tmpl:replace-blocks($node/node(), $blocks)
                }
            default return
                $node
};