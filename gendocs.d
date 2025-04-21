#!/usr/bin/env rdmd
// Written in the D programming language

/++
    This is a program for generating the html version of the man page
    - mainly so that it can be put on jmdavisprog.com, but it does provide a
    way to get an html version of the man page for anyone who wants it.

    This is a stripped down and tweaked version of the program I use for
    generating the html documentation for my libraries (e.g. for dxml).
    ddoc isn't strictly necessary for generating the html in this case, because
    this isn't generating documentation from the source code (as would be being
    done with a library), but the ddoc machinery makes it possible to add a
    header and footer to the html, which the program for generating the html
    for jmdavisprog.com does by providing an additional ddoc file which defines
    the ddoc macros used to generate the header and footer (whereas if they're
    not defined, then that portion just ends up blank). And since css files are
    included with the ddoc, that affects how the html looks.

    dmd is required for the ddoc stuff to work, and mandoc is required to do
    the actual conversion of the man page to html.

    The manPage enum tells the program what the file for the man page is.

    The generated documentation goes in the "docs" directory (which is deleted
    before documentation generation to ensure a clean build).

    It's expected that any .ddoc files being used will be in the "ddoc"
    directory.

    In addition, the program expects there to be a "source_docs" directory. Any
    .dd files that are there will have corresponding .html files generated for
    them (e.g. for generating index.html), and any other files or directories
    (e.g. a "css" or "js" folder) will be copied over to the "docs" folder.

    With this stripped down version of gendocs.d, the index.dd file in
    source_docs uses a macro called MAN_PAGE, and gendocs.d creates a temporary
    .ddoc file which defines the MAN_PAGE macro with the contents of the man
    page as html as provided by mandoc. So, when index.html is generated, the
    man page is the core of index.html.

    Copyright: Copyright 2017 - 2025
    License:   $(WEB www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
    Author:   Jonathan M Davis
  +/
module gendocs;

import std.range.primitives;

enum manPage = "bemgr.8";
enum docsDir = "docs";
enum ddocDir = "ddoc";
enum sourceDocsDir = "source_docs";

int main(string[] args)
{
    import std.exception : enforce;
    import std.file : exists, mkdir, remove, rmdirRecurse;
    import std.format : format;

    try
    {
        enforce(manPage, format!"%s is missing"(manPage));
        enforce(ddocDir.exists, "ddoc directory is missing");
        enforce(sourceDocsDir.exists, "source_docs directory is missing");

        if(docsDir.exists)
            rmdirRecurse(docsDir);
        mkdir(docsDir);

        auto manPageDDoc = genManPageDDoc();
        scope(exit) remove(manPageDDoc);

        auto ddocFiles = getDdocFiles();
        processSourceDocsDir(sourceDocsDir, docsDir, ddocFiles);
    }
    catch(Exception e)
    {
        import std.stdio : stderr, writeln;
        stderr.writeln(e.msg);
        return -1;
    }

    return 0;
}

void processSourceDocsDir(string sourceDir, string targetDir, string[] ddocFiles)
{
    import std.file : copy, dirEntries, mkdir, SpanMode;
    import std.path : baseName, extension, buildPath, setExtension;

    foreach(de; dirEntries(sourceDir, SpanMode.shallow))
    {
        auto target = buildPath(targetDir, de.baseName);
        if(de.isDir)
        {
            mkdir(target);
            processSourceDocsDir(de.name, target, ddocFiles);
        }
        else if(de.isFile)
        {
            if(de.name.extension == ".dd")
                genDdoc(de.name, target.setExtension(".html"), ddocFiles);
            else
                copy(de.name, target);
        }
    }
}

void genDdoc(string sourceFile, string htmlFile, string[] ddocFiles)
{
    import std.process : execute;
    auto result = execute(["dmd", "-o-", "-Isource/", "-Df" ~ htmlFile, sourceFile] ~ ddocFiles);
    if(result.status != 0)
        throw new Exception("dmd failed:\n" ~ result.output);
}

string[] getDdocFiles()
{
    import std.algorithm.iteration : map;
    import std.array : array;
    import std.file : dirEntries, SpanMode;

    return dirEntries("ddoc", SpanMode.shallow).map!(a => a.name)().array();
}

string genManPageDDoc()
{
    import std.array : appender;
    import std.exception : enforce;
    import std.file : write;
    import std.format : format;
    import std.path : buildPath;
    import std.process : esfn = escapeShellFileName, executeShell;

    auto result = executeShell(format!"mandoc -T html -O fragment %s"(esfn(manPage)));
    enforce(result.status == 0, format!"Failed to generate html with mandoc: %s"(result.output));
    auto manpageHTML = result.output;

    auto output = appender!string();
    put(output, "MAN_PAGE=\n");
    put(output, manpageHTML);
    put(output, "\n_=");

    auto manPageDDoc = buildPath(ddocDir, "manpage.ddoc");
    write(manPageDDoc, output.data);

    return manPageDDoc;
}
