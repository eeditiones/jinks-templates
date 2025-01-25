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
declare variable $tmpl:CONFIG_EXTENDS := "extends";
declare variable $tmpl:CONFIG_USE := "use";
declare variable $tmpl:CONFIG_IGNORE_USE := "ignoreUse";

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
    "\[%\+?\s*(block)\s+(.+?)%\]",
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
            map {}
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
                    case "block" return
                        let $name := $token/fn:group[2] => normalize-space()
                        return
                            <block name="{$name}">
                            {
                                if (starts-with($type/parent::fn:match, "[%+")) then
                                    attribute { "append" } { "true" }
                                else
                                    ()
                            }
                            </block>
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
declare function tmpl:parse($tokens as item()*, $resolver as function(*)?) {
    <ast>{tmpl:do-parse($tokens, $resolver)}</ast>
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
                case element(endfor) | element(endlet) | element(endif) | element(endblock) | element(comment) return
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
    $namespaces as map(*)?,$resolver as function(*)?,  $incomingBlocks as element(block)*) {
    let $prolog := tmpl:prolog($ast, $modules, $namespaces, $resolver) => string-join('&#10;')
    let $body := $config?block?start(()) || string-join(tmpl:emit($config, $ast)) || $config?block?end(())
    let $code := string-join((tmpl:vars($params), $body), "&#10;")
    let $blocks :=
        <blocks xmlns="">
        {
            for $block in $incomingBlocks[not(@name = 'content')]
            return
                <block name="{$block/@name}">
                {
                    tmpl:escape-block($block/node())
                }
                </block>
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
                case element(unwrap) return
                    $config?enclose?start($node)
                    || "tmpl:unwrap(" || tmpl:emit($config, $node/node()) || ")"
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

declare function tmpl:unwrap($nodes as node()*) {
    if (count($nodes) = 1) then
        $nodes/node()
    else
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
 : Parses a template into an abstract syntax tree (AST), recursively merging extended templates and blocks.
 :)
declare function tmpl:to-ast($template as xs:string, $params as map(*), $config as map(*), $blocks as element(block)*) {
    let $localContext := tmpl:frontmatter($template)
    let $extends := tmpl:templating-param($localContext, $tmpl:CONFIG_EXTENDS)
    let $context := tmpl:merge-deep(($params, $localContext))
    let $incomingBlocks := (
        $blocks,
        tmpl:external-blocks($config, $context, $config?resolver)
    )
    (: Remove "extends" from templating params to avoid infinite recursion :)
    let $modContext := map:merge((
        $context,
        if (map:contains($context, $tmpl:CONFIG_PROPERTY)) then
            map {
                "templating": map:remove($context?($tmpl:CONFIG_PROPERTY), $tmpl:CONFIG_EXTENDS)
                    => map:remove($tmpl:CONFIG_USE)
            }
        else
            ()
    ))
    let $ast := tmpl:tokenize($template) => tmpl:parse($config?resolver)
    let $ast := tmpl:expand-blocks($ast, $incomingBlocks, false())
    return
        if ($extends) then
            let $contentBlock :=
                <block name="content">
                {
                    if ($localContext?($tmpl:CONFIG_PROPERTY)?strip-root) then
                        attribute { "unwrap" } { "true" }
                    else
                        (),
                    tmpl:get-content($ast)
                }
                </block>
            return
                if (empty($config?resolver)) then
                    error($tmpl:ERROR_EXTENDS, "Extends is not available in this templating context")
                else
                    let $baseTemplate := $config?resolver($extends)
                    return
                        if (exists($baseTemplate)) then
                            tmpl:to-ast($baseTemplate?content, $modContext, $config, ($incomingBlocks except $incomingBlocks[@name = 'content'], $ast//block, $contentBlock))
                        else
                            error($tmpl:ERROR_EXTENDS, "Extended template " || $extends || " not found")
        else
            map {
                "ast": tmpl:expand-blocks($ast, $incomingBlocks, true()),
                "context": $modContext,
                "blocks": $blocks
            }
};

declare %private function tmpl:expand-blocks($ast as node()*, $blocks as element(block)*) {
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
                            for $block in reverse($blocks)
                            return
                                if ($block/@unwrap) then
                                    <unwrap>{ $block/node() }</unwrap>
                                else
                                    $block/node()
                        else if ($applyDefaults) then
                            $node/node()
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

declare %private function tmpl:get-content($ast as node()*) {
    for $node in $ast
    return
        typeswitch($node)
            case element(block) return
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
                (tmpl:tokenize($template?content) => tmpl:parse($resolver))//block
            else
                error($tmpl:ERROR_INCLUDE, "Included template " || $file || " not found")
    else
        ()
};

declare function tmpl:process($template as xs:string, $params as map(*), $config as map(*)) {
    tmpl:process($template, $params, $config, ())
};

declare function tmpl:process($template as xs:string, $params as map(*), $config as map(*), $blocks as element(block)*) {
    let $ast := tmpl:to-ast($template, $params, $config, $blocks)
    let $modules := map:merge((
        $config?modules,
        if (not($config?($tmpl:CONFIG_IMPORTS)) and exists($ast?context?($tmpl:CONFIG_PROPERTY))) then
            $ast?context?($tmpl:CONFIG_PROPERTY)?modules
        else
            (),
        tmpl:imported-modules($ast?ast, $config?resolver)
    ))
    let $namespaces := map:merge((
        $config?namespaces,
        if (exists($ast?context?($tmpl:CONFIG_PROPERTY))) then
            $ast?context?($tmpl:CONFIG_PROPERTY)?namespaces
        else
            ()
    ))
    let $mode := if ($config?plainText) then $tmpl:TEXT_MODE else $tmpl:XML_MODE
    let $code := tmpl:generate($mode, $ast?ast, $ast?context, $modules, $namespaces, $config?resolver, $ast?blocks)
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
                let $byId := map:merge(for $value in $values return map:entry(map:get($value, "id"), $value))
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