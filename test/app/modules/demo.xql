xquery version "3.1";

module namespace demo="https://tei-publisher.com/jinks/xquery/demo";

declare function demo:sysinfo($title as xs:string) {
    <ul>
        <li>Application title: {$title}</li>
    </ul>
};

declare function demo:sysinfo2() {
    map {
        "version": system:get-version(),
        "build": system:get-build()
    }
};

declare function demo:tei() {
    <TEI xmlns="http://www.tei-c.org/ns/1.0">
        <teiHeader>
            <fileDesc>
                <titleStmt>
                    <title>TEI Publisher</title>
                </titleStmt>
                <publicationStmt>
                    <p>Published by TEI Publisher</p>
                </publicationStmt>
            </fileDesc>
        </teiHeader>
        <text>
            <body>
                <p>TEI Publisher is a web-based application for creating and publishing TEI documents.</p>
            </body>
        </text>
    </TEI>
};