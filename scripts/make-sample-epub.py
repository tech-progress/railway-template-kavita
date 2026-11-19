#!/usr/bin/env python3
"""Write a minimal valid EPUB 3 file for the smoke test.

Usage: make-sample-epub.py OUTPUT_PATH TITLE
"""
import sys
import zipfile
from xml.sax.saxutils import escape

if len(sys.argv) != 3:
    sys.exit("Usage: make-sample-epub.py OUTPUT_PATH TITLE")

output, title = sys.argv[1], escape(sys.argv[2])

container = """<?xml version="1.0" encoding="UTF-8"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>
"""

opf = f"""<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="bookid">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:identifier id="bookid">urn:uuid:5b0c3d6e-6f2a-4b8e-9d55-2f4f8f3f6a01</dc:identifier>
    <dc:title>{title}</dc:title>
    <dc:creator>Railway Template Smoke Test</dc:creator>
    <dc:language>en</dc:language>
    <meta property="dcterms:modified">2026-01-01T00:00:00Z</meta>
  </metadata>
  <manifest>
    <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
    <item id="chapter1" href="chapter1.xhtml" media-type="application/xhtml+xml"/>
  </manifest>
  <spine>
    <itemref idref="chapter1"/>
  </spine>
</package>
"""

nav = """<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
  <head><title>Contents</title></head>
  <body>
    <nav epub:type="toc"><ol><li><a href="chapter1.xhtml">Chapter 1</a></li></ol></nav>
  </body>
</html>
"""

chapter = f"""<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml">
  <head><title>Chapter 1</title></head>
  <body><h1>{title}</h1><p>This book was uploaded to verify a Kavita library scan.</p></body>
</html>
"""

with zipfile.ZipFile(output, "w") as epub:
    # The mimetype entry must come first and must not be compressed.
    epub.writestr("mimetype", "application/epub+zip", compress_type=zipfile.ZIP_STORED)
    epub.writestr("META-INF/container.xml", container, compress_type=zipfile.ZIP_DEFLATED)
    epub.writestr("OEBPS/content.opf", opf, compress_type=zipfile.ZIP_DEFLATED)
    epub.writestr("OEBPS/nav.xhtml", nav, compress_type=zipfile.ZIP_DEFLATED)
    epub.writestr("OEBPS/chapter1.xhtml", chapter, compress_type=zipfile.ZIP_DEFLATED)
