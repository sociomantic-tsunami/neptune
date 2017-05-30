/*******************************************************************************

    Provides function to turn all aggregated information into one HTML
    report page

    Copyright:
        Copyright (c) 2009-2016 Sociomantic Labs GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module overview.htmlreport;

import overview.repository;
import semver.Version;

import std.variant;

/**
    Generates HTML table with rows being all projects and columns
    being potential dependencies (== all library project) with current
    dependency version string put into intersection cell.

    Params:
        projects = mapping of project names to matching repo metadata
        path = path to write HTML report to

 **/
void generateHTMLReport ( const Repository[] projects, string path )
{
    // generates table header with column per project name

    string genTableHeader ( )
    {
        import std.algorithm : map, filter;
        import std.format;
        import std.range : join;

        return format(
            "<tr><th></th>%s</tr>\n",
            projects
                .filter!(proj => proj.library)
                .map!(proj => format("<th onclick='sortByThisColumn(this)'>%s</th>", proj.name))
                .join()
        );
    }

    // function to generate one table <tr> for a specific repository/project
    // (listing all its dependency versions)

    string genTableRow ( ref const Repository proj )
    {
        // maps dependency project to string that has to be put
        // in matching table cell

        string getDependencyVersion ( ref const Repository dependency )
        {
            auto ver = dependency.name in proj.dependencies;

            if (ver is null)
                return "";

            return visit!(
                (Version v)   => v.toString(),
                (SHANotFound v) => v.sha[0..8]
            )(*ver);
        }

        import std.algorithm : map, filter;
        import std.range : join;
        import std.format;

        return format(
            "<tr><td>%s</td>%s</tr>",
            proj.name,
            projects
                .filter!(proj => proj.library)
                .map!getDependencyVersion
                .map!(ver => format("<td>%s</td>", ver))
                .join()
        );
    }

    // generate rest of the table

    import std.format;
    import std.algorithm : map;
    import std.range : join;
    import std.file : write;

    string tableBody = projects
        .map!genTableRow
        .join("\n");

    write(path, format(reportTemplate, genTableHeader() ~ tableBody));
}

/*******************************************************************************

    Template used to generate final report

*******************************************************************************/

static immutable reportTemplate = `
<html>
<head>
<style>
table#dependencies td {
    min-width: 10em;
    border: 1px solid gray;
}
</style>
<script>
function sortByThisColumn ( header_column )
{
    // find index of the column to sort by
    var header = header_column.parentElement;
    var header_columns = Array.prototype.slice.call(header.childNodes);
    var column_index = header_columns.indexOf(header_column);

    // get all rows but first as array and sort
    var rows = header.parentElement.querySelectorAll("tr");
    rows = Array.prototype.slice.call(rows);
    rows = rows.slice(1, rows.length);
    rows.sort(
        function(row1, row2) {
            var ver1 = row1.childNodes[column_index].innerText
            var ver2 = row2.childNodes[column_index].innerText;

            if (ver1 != ver2)
                return ver2.localeCompare(ver1);

            return row2.childNodes[0].innerText.localeCompare(
                row1.childNodes[0].innerText);
        }
    );

    // clear all rows and add again
    var table = header.parentElement;

    while (table.hasChildNodes())
        table.removeChild(table.firstChild);

    table.appendChild(header);
    for (row of rows)
        table.appendChild(row);
}
</script>
</head>
<body>
<table id='dependencies'>
%s
</table>
</body>
</html>
`;
