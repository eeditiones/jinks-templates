xquery version "3.1";

declare namespace api="https://tei-publisher.com/xquery/api";
declare namespace output="http://www.w3.org/2010/xslt-xquery-serialization";
declare namespace expath="http://expath.org/ns/pkg";

import module namespace roaster="http://e-editiones.org/roaster";
import module namespace auth="http://e-editiones.org/roaster/auth";
import module namespace errors = "http://e-editiones.org/roaster/errors";
import module namespace tmpl="http://e-editiones.org/xquery/templates";

declare option output:method "html5";
declare option output:media-type "text/html";
declare option output:indent "no";

(:
    Determine the application root collection from the current module load path.
:)
declare variable $api:app-root :=
    let $rawPath := system:get-module-load-path()
    let $modulePath :=
        (: strip the xmldb: part :)
        if (starts-with($rawPath, "xmldb:exist://")) then
            if (starts-with($rawPath, "xmldb:exist://embedded-eXist-server")) then
                substring($rawPath, 36)
            else
                substring($rawPath, 15)
        else
            $rawPath
    return
        substring-before($modulePath, "/modules")
;

declare function api:resolver($relPath as xs:string) as map(*)? {
    let $path := $api:app-root || "/" || $relPath
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

declare function api:expand-template($request as map(*)) {
    let $template := $request?body?template
    let $params := head(($request?body?params, map {}))
    return
        try {
            tmpl:process($template, $params, map {
                "plainText": not($request?body?mode = ('html', 'xml')), 
                "resolver": api:resolver#1, 
                "debug": true()
            })
        } catch * {
            if (exists($err:value)) then
                roaster:response(500, "application/json", $err:value)
            else
                roaster:response(500, "application/json", $err:description)
        }
};

let $lookup := function($name as xs:string) {
    try {
        function-lookup(xs:QName($name), 1)
    } catch * {
        ()
    }
}
let $resp := roaster:route("modules/api.json", $lookup)
return
    $resp