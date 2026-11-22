;; Copyright © 2026 Amirouche A. BOUBEKKI <amirouche at hyper dev>
(library (letloop html justhtml)
  (export html-entity-named-entries
          html-entity-legacy-names
          html-entity-numeric-replacement-entries
          html-svg-tag-name-adjustment-entries
          html-svg-attribute-adjustment-entries
          html-mathml-attribute-adjustment-entries
          html-foreign-attribute-adjustment-entries
          html-formatting-element-names
          html-special-element-names
          html-foreign-breakout-element-names
          html-void-element-names
          html-implied-end-tag-names
          html-default-scope-terminator-names
          html-table-scope-terminator-names
          html-quirky-public-prefixes
          html-quirky-public-matches
          html-quirky-system-matches
          html-limited-quirky-public-prefixes
          html4-public-prefixes
          html-entity-named-ref
          html-entity-legacy-name?
          html-entity-numeric-decode
          html-entity-text-decode
          char-ascii-alphabetic?
          char-ascii-digit?
          char-ascii-alphanumeric?
          char-ascii-hexadecimal-digit?
          char-ascii-lowercase
          string-ascii-lowercase
          string-ascii-equal?
          string-ascii-prefix?
          ~check-entities-numeric-missing-semicolon
          ~check-entities-numeric-hexadecimal-c1
          ~check-entities-numeric-noncharacter
          ~check-entities-legacy-prefix-with-semicolon
          ~check-entities-legacy-without-semicolon
          ~check-entities-legacy-prefix-without-semicolon
          ~check-entities-named-basic
          ~check-entities-numeric-out-of-range
          ~check-entities-numeric-surrogate
          ~check-entities-numeric-null
          ~check-entities-attribute-ambiguous-ampersand
          ~check-entities-attribute-semicolon-terminated
          ~check-entities-bare-ampersand
          ~check-entities-multi-character-value
          html-scanner-ascii-startswith?
          html-scanner-ascii-find
          html-scanner-ascii-rfind
          html-scanner-tag-end-find
          html-scanner-rawtext-end-tag-find
          html-scanner-script-end-tag-find
          html-scanner-script-start-marker-find
          html-space-character?
          html-tag-end-name-stop-character?
          ~check-scanner-ascii-find
          ~check-scanner-ascii-startswith
          ~check-scanner-ascii-rfind
          ~check-scanner-tag-end-unquoted
          ~check-scanner-tag-end-quoted
          ~check-scanner-tag-end-missing
          ~check-scanner-rawtext-end-tag
          ~check-scanner-rawtext-end-tag-prefix
          ~check-scanner-rawtext-end-tag-missing
          ~check-scanner-script-end-tag-plain
          ~check-scanner-script-end-tag-escaped
          ~check-scanner-script-end-tag-double-escaped
          ~check-scanner-script-start-marker
          html-source-preprocess
          html-tokenizer-make
          html-tokenizer-next
          html-tokenizer-state-set!
          html-tokenizer-content-state-for-tag
          html-tokenizer-last-start-tag-set!
          html-tokenizer-foreign-set!
          html-tokenizer-scripting-set!
          token-start-tag?
          token-start-tag-make
          token-start-tag-name
          token-start-tag-attributes
          token-start-tag-self-closing?
          token-end-tag?
          token-end-tag-make
          token-end-tag-name
          token-character?
          token-character-make
          token-character-text
          token-comment?
          token-comment-make
          token-comment-text
          token-doctype?
          token-doctype-make
          token-doctype-name
          token-doctype-public-id
          token-doctype-system-id
          token-doctype-force-quirks?
          token-end-of-file?
          token-end-of-file-make
          token-processing-instruction?
          token-processing-instruction-make
          token-processing-instruction-target
          token-processing-instruction-data
          html-tokenize
          ~check-tokenizer-preprocessing
          ~check-tokenizer-basic-tags
          ~check-tokenizer-attributes
          ~check-tokenizer-comments
          ~check-tokenizer-doctype
          ~check-tokenizer-rawtext
          ~check-tokenizer-script-data
          ~check-tokenizer-rcdata
          ~check-tokenizer-cdata
          ~check-tokenizer-state-transitions
          ~check-tokenizer-fixture-states
          html->sxml
          html-parse
          html-node->sxml
          html-sxml->test-format
          html-sxml->html
          html-doctype-quirks-mode
          html-node?
          html-node-kind
          html-node-name
          html-node-namespace
          html-node-attributes
          html-node-children
          html-node-data
          html-node-content
          ~check-parser-minimal-document
          ~check-parser-implied-elements
          ~check-parser-doctype
          ~check-parser-text-merge
          ~check-sxml-boolean-attribute
          ~check-sxml-comment
          ~check-sxml-doctype-public-only
          ~check-sxml-template
          ~check-sxml-foreign-content
          ~check-serializer-attribute-order
          ~check-html-serializer
          ~check-html-serializer-round-trip
          ~check-quirks-mode-detection
          ~check-parser-fragment
          html-fixture-check
          html-fixture-entries
          html-fixtures-report
          ~check-character-preprocessing-0
          ~check-character-preprocessing-1
          ~check-character-preprocessing-2
          ~check-character-preprocessing-3
          ~check-character-preprocessing-4
          ~check-character-preprocessing-5
          ~check-character-preprocessing-6
          ~check-character-preprocessing-7
          ~check-character-preprocessing-8
          ~check-character-preprocessing-9
          ~check-character-preprocessing-10
          ~check-character-preprocessing-11
          ~check-character-preprocessing-12
          ~check-character-preprocessing-13
          ~check-character-preprocessing-14
          ~check-character-preprocessing-15
          ~check-character-preprocessing-16
          ~check-character-preprocessing-17
          ~check-character-preprocessing-18
          ~check-character-preprocessing-19
          ~check-character-preprocessing-20
          ~check-character-preprocessing-21
          ~check-document-shell-recovery-0
          ~check-document-shell-recovery-1
          ~check-document-shell-recovery-2
          ~check-document-shell-recovery-3
          ~check-document-shell-recovery-4
          ~check-document-shell-recovery-5
          ~check-document-shell-recovery-6
          ~check-document-shell-recovery-7
          ~check-document-shell-recovery-8
          ~check-document-shell-recovery-9
          ~check-document-shell-recovery-10
          ~check-document-shell-recovery-11
          ~check-document-shell-recovery-12
          ~check-document-shell-recovery-13
          ~check-document-shell-recovery-14
          ~check-document-shell-recovery-15
          ~check-document-shell-recovery-16
          ~check-document-shell-recovery-17
          ~check-document-shell-recovery-18
          ~check-document-shell-recovery-19
          ~check-document-shell-recovery-20
          ~check-document-shell-recovery-21
          ~check-document-shell-recovery-22
          ~check-document-shell-recovery-23
          ~check-document-shell-recovery-24
          ~check-document-shell-recovery-25
          ~check-document-shell-recovery-26
          ~check-document-shell-recovery-27
          ~check-document-shell-recovery-28
          ~check-document-shell-recovery-29
          ~check-document-shell-recovery-30
          ~check-document-shell-recovery-31
          ~check-foreign-content-0
          ~check-foreign-content-1
          ~check-foreign-content-2
          ~check-foreign-content-3
          ~check-foreign-content-4
          ~check-foreign-content-5
          ~check-foreign-content-6
          ~check-foreign-content-7
          ~check-foreign-content-8
          ~check-foreign-content-9
          ~check-foreign-content-10
          ~check-foreign-content-11
          ~check-foreign-content-12
          ~check-foreign-content-13
          ~check-foreign-content-14
          ~check-foreign-content-15
          ~check-foreign-content-16
          ~check-foreign-content-17
          ~check-foreign-content-18
          ~check-foreign-content-19
          ~check-foreign-content-20
          ~check-foreign-content-21
          ~check-foreign-content-22
          ~check-foreign-content-23
          ~check-foreign-content-24
          ~check-foreign-content-25
          ~check-foreign-content-26
          ~check-foreign-content-27
          ~check-foreign-stack-recovery-0
          ~check-foreign-stack-recovery-1
          ~check-foreign-stack-recovery-2
          ~check-frameset-recovery-0
          ~check-frameset-recovery-1
          ~check-frameset-recovery-2
          ~check-frameset-recovery-3
          ~check-frameset-recovery-4
          ~check-frameset-recovery-5
          ~check-frameset-recovery-6
          ~check-frameset-recovery-7
          ~check-frameset-recovery-8
          ~check-frameset-recovery-9
          ~check-frameset-recovery-10
          ~check-frameset-recovery-11
          ~check-frameset-recovery-12
          ~check-frameset-recovery-13
          ~check-frameset-recovery-14
          ~check-frameset-recovery-15
          ~check-frameset-recovery-16
          ~check-frameset-recovery-17
          ~check-frameset-recovery-18
          ~check-frameset-recovery-19
          ~check-frameset-recovery-20
          ~check-frameset-recovery-21
          ~check-frameset-recovery-22
          ~check-head-noscript-recovery-0
          ~check-head-noscript-recovery-1
          ~check-head-noscript-recovery-2
          ~check-head-noscript-recovery-3
          ~check-head-noscript-recovery-4
          ~check-iframe-srcdoc-0
          ~check-in-body-recovery-0
          ~check-in-body-recovery-1
          ~check-in-body-recovery-2
          ~check-in-body-recovery-3
          ~check-in-body-recovery-4
          ~check-in-body-recovery-5
          ~check-in-body-recovery-6
          ~check-in-body-recovery-7
          ~check-in-body-recovery-8
          ~check-in-body-recovery-9
          ~check-in-body-recovery-10
          ~check-in-body-recovery-11
          ~check-in-body-recovery-12
          ~check-in-body-recovery-13
          ~check-raw-text-recovery-0
          ~check-raw-text-recovery-1
          ~check-raw-text-recovery-2
          ~check-raw-text-recovery-3
          ~check-raw-text-recovery-4
          ~check-raw-text-recovery-5
          ~check-raw-text-recovery-6
          ~check-raw-text-recovery-7
          ~check-raw-text-recovery-8
          ~check-raw-text-recovery-9
          ~check-raw-text-recovery-10
          ~check-raw-text-recovery-11
          ~check-raw-text-recovery-12
          ~check-raw-text-recovery-13
          ~check-raw-text-recovery-14
          ~check-raw-text-recovery-15
          ~check-raw-text-recovery-16
          ~check-raw-text-recovery-17
          ~check-select-recovery-0
          ~check-select-recovery-1
          ~check-select-recovery-2
          ~check-select-recovery-3
          ~check-select-recovery-4
          ~check-select-recovery-5
          ~check-select-recovery-6
          ~check-select-recovery-7
          ~check-select-recovery-8
          ~check-select-recovery-9
          ~check-select-recovery-10
          ~check-select-recovery-11
          ~check-select-recovery-12
          ~check-select-recovery-13
          ~check-select-recovery-14
          ~check-select-recovery-15
          ~check-select-recovery-16
          ~check-select-recovery-17
          ~check-select-recovery-18
          ~check-select-recovery-19
          ~check-selectedcontent-0
          ~check-selectedcontent-1
          ~check-selectedcontent-2
          ~check-selectedcontent-3
          ~check-selectedcontent-4
          ~check-table-recovery-0
          ~check-table-recovery-1
          ~check-table-recovery-2
          ~check-table-recovery-3
          ~check-table-recovery-4
          ~check-table-recovery-5
          ~check-table-recovery-6
          ~check-table-recovery-7
          ~check-table-recovery-8
          ~check-table-recovery-9
          ~check-table-recovery-10
          ~check-table-recovery-11
          ~check-table-recovery-12
          ~check-table-recovery-13
          ~check-template-recovery-0
          ~check-template-recovery-1
          ~check-template-recovery-2
          ~check-template-recovery-3
          ~check-template-recovery-4
          ~check-template-recovery-5
          ~check-template-recovery-6
          ~check-template-recovery-7
          ~check-template-recovery-8
          ~check-template-recovery-9
          ~check-template-recovery-10
          ~check-template-recovery-11
          ~check-template-recovery-12
          ~check-template-recovery-13
          ~check-template-recovery-14
          ~check-template-recovery-15
          ~check-template-recovery-16
          ~check-template-recovery-17
          ~check-template-recovery-18
          ~check-template-recovery-19
          ~check-template-recovery-20
          ~check-template-recovery-21
          ~check-template-recovery-22
          ~check-template-recovery-23
          ~check-template-recovery-24
          ~check-template-recovery-25
          ~check-template-recovery-26
          ~check-template-recovery-27
          ~check-template-recovery-28
          ~check-template-recovery-29
          ~check-template-recovery-30
          ~check-template-recovery-31
          ~check-template-recovery-32
          ~check-template-recovery-33
          ~check-template-recovery-34
          ~check-template-recovery-35
          ~check-template-recovery-36
          ~check-template-recovery-37
          ~check-template-recovery-38
          ~check-template-recovery-39
          ~check-template-recovery-40
          ~check-template-recovery-41
          ~check-template-recovery-42
          ~check-template-recovery-43
          ~check-template-recovery-44
          ~check-template-recovery-45
          ~check-template-recovery-46
          ~check-tokenizer-recovery-0
          ~check-tokenizer-recovery-1
          ~check-tokenizer-recovery-2
          ~check-tokenizer-recovery-3
          ~check-tokenizer-recovery-4
          ~check-tokenizer-recovery-5
          ~check-tokenizer-recovery-6
          ~check-tokenizer-recovery-7
          ~check-tokenizer-recovery-8
          ~check-tokenizer-recovery-9
          ~check-tokenizer-recovery-10
          ~check-tokenizer-recovery-11
          ~check-tokenizer-recovery-12
          ~check-tokenizer-recovery-13
          ~check-tokenizer-recovery-14
          ~check-tokenizer-recovery-15
          ~check-tokenizer-recovery-16
          ~check-tokenizer-recovery-17
          ~check-tokenizer-recovery-18
          ~check-tokenizer-recovery-19
          ~check-tokenizer-recovery-20
          ~check-tokenizer-recovery-21
          ~check-tokenizer-recovery-22
          ~check-tokenizer-recovery-23
          ~check-xml-coercion-0
          ~check-xml-coercion-1
          ~check-xml-coercion-2
          ~check-xml-coercion-3
          ~check-xml-coercion-4
          ~check-xml-coercion-5)
  (import (chezscheme))

  ;; A Chez Scheme port of the HTML5 parsing engine of justhtml
  ;; (submodules/justhtml), ported from commit
  ;; af685d49767b948384a18159b45edf713559f005 (tag v3.10.0).
  ;;
  ;; Input is a Unicode string of already-decoded HTML text; output is a
  ;; single SXML tree.  Six sections follow, each testable in isolation and
  ;; each with its own ~check procedures.  Sections 1 to 5 are in this file;
  ;; their checks and all of section 6 are in justhtml.check.scm:
  ;;
  ;;   1. static tables    -- generated, see scripts/html-tables-generate.py
  ;;   2. character references (WHATWG 13.2.5)
  ;;   3. scanner          -- pure string search helpers
  ;;   4. tokenizer        -- the WHATWG tokenizer state machine
  ;;   5. tree construction, SXML assembly and serialization (WHATWG 13.2.6)
  ;;   6. tree-construction fixtures -- generated, see
  ;;      scripts/html-fixtures-generate.py
  ;;
  ;; The static tables come first because a library body is a letrec*: the
  ;; hash tables built from them are initialized further down.
  ;;
  ;; This file was imported from the atlas-stoa repository. Three paths
  ;; named in its comments stay there and were not brought over:
  ;; scripts/html-tables-generate.py, scripts/html-fixtures-generate.py
  ;; and spec/justhtml-sxml-prompt.md. submodules/justhtml is in this
  ;; repository, pinned at the commit above.
  ;;
  ;; If justhtml upstream moves (new pinned commit under submodules/justhtml):
  ;; scripts/html-tables-generate.py and scripts/html-fixtures-generate.py
  ;; still write their own separate html-tables.scm/html-fixtures.scm files
  ;; (this merge didn't repoint them) -- re-run both, diff the freshly
  ;; generated files against sections 1 and 6 below, and hand-merge whatever
  ;; changed back into this file. There is no automated merge step.
  ;;
  ;; ------------------------------------------------------------------
  ;;
  ;; Portions of this file are a Chez Scheme port of the parsing behavior of
  ;; justhtml (https://github.com/EmilStenstrom/justhtml), used as a
  ;; behavioral reference per spec/justhtml-sxml-prompt.md.
  ;;
  ;; justhtml is MIT-licensed:
  ;;
  ;; MIT License
  ;;
  ;; Copyright (c) 2025 Emil Stenström (JustHTML)
  ;; Copyright (c) 2014-2017, The html5ever Project Developers (html5ever inspiration)
  ;; Copyright (c) 2006-2013 James Graham, Sam Sneddon, and
  ;; other contributors (html5lib-tests)
  ;;
  ;; Permission is hereby granted, free of charge, to any person obtaining a copy
  ;; of this software and associated documentation files (the "Software"), to deal
  ;; in the Software without restriction, including without limitation the rights
  ;; to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
  ;; copies of the Software, and to permit persons to whom the Software is
  ;; furnished to do so, subject to the following conditions:
  ;;
  ;; The above copyright notice and this permission notice shall be included in all
  ;; copies or substantial portions of the Software.
  ;;
  ;; THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
  ;; IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
  ;; FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
  ;; AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
  ;; LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
  ;; OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
  ;; SOFTWARE.

  ;; ====================================================================
  ;; Section 1 -- static tables (generated)
  ;; ====================================================================
  ;; Generated file -- do not edit by hand.
  ;;
  ;; Static tables extracted mechanically from
  ;; submodules/justhtml/src/justhtml/core/entities.py and
  ;; submodules/justhtml/src/justhtml/core/constants.py (justhtml v3.10.0,
  ;; af685d4).  The named entity table itself comes from Python's
  ;; html.entities.html5 dictionary, with trailing semicolons stripped from
  ;; the keys, exactly as justhtml's entities.py does.

  ;; 2125 named character references
  (define html-entity-named-entries
    '#(
      ("AElig" . "\xC6;")
      ("AMP" . "&")
      ("Aacute" . "\xC1;")
      ("Abreve" . "\x102;")
      ("Acirc" . "\xC2;")
      ("Acy" . "\x410;")
      ("Afr" . "\x1D504;")
      ("Agrave" . "\xC0;")
      ("Alpha" . "\x391;")
      ("Amacr" . "\x100;")
      ("And" . "\x2A53;")
      ("Aogon" . "\x104;")
      ("Aopf" . "\x1D538;")
      ("ApplyFunction" . "\x2061;")
      ("Aring" . "\xC5;")
      ("Ascr" . "\x1D49C;")
      ("Assign" . "\x2254;")
      ("Atilde" . "\xC3;")
      ("Auml" . "\xC4;")
      ("Backslash" . "\x2216;")
      ("Barv" . "\x2AE7;")
      ("Barwed" . "\x2306;")
      ("Bcy" . "\x411;")
      ("Because" . "\x2235;")
      ("Bernoullis" . "\x212C;")
      ("Beta" . "\x392;")
      ("Bfr" . "\x1D505;")
      ("Bopf" . "\x1D539;")
      ("Breve" . "\x2D8;")
      ("Bscr" . "\x212C;")
      ("Bumpeq" . "\x224E;")
      ("CHcy" . "\x427;")
      ("COPY" . "\xA9;")
      ("Cacute" . "\x106;")
      ("Cap" . "\x22D2;")
      ("CapitalDifferentialD" . "\x2145;")
      ("Cayleys" . "\x212D;")
      ("Ccaron" . "\x10C;")
      ("Ccedil" . "\xC7;")
      ("Ccirc" . "\x108;")
      ("Cconint" . "\x2230;")
      ("Cdot" . "\x10A;")
      ("Cedilla" . "\xB8;")
      ("CenterDot" . "\xB7;")
      ("Cfr" . "\x212D;")
      ("Chi" . "\x3A7;")
      ("CircleDot" . "\x2299;")
      ("CircleMinus" . "\x2296;")
      ("CirclePlus" . "\x2295;")
      ("CircleTimes" . "\x2297;")
      ("ClockwiseContourIntegral" . "\x2232;")
      ("CloseCurlyDoubleQuote" . "\x201D;")
      ("CloseCurlyQuote" . "\x2019;")
      ("Colon" . "\x2237;")
      ("Colone" . "\x2A74;")
      ("Congruent" . "\x2261;")
      ("Conint" . "\x222F;")
      ("ContourIntegral" . "\x222E;")
      ("Copf" . "\x2102;")
      ("Coproduct" . "\x2210;")
      ("CounterClockwiseContourIntegral" . "\x2233;")
      ("Cross" . "\x2A2F;")
      ("Cscr" . "\x1D49E;")
      ("Cup" . "\x22D3;")
      ("CupCap" . "\x224D;")
      ("DD" . "\x2145;")
      ("DDotrahd" . "\x2911;")
      ("DJcy" . "\x402;")
      ("DScy" . "\x405;")
      ("DZcy" . "\x40F;")
      ("Dagger" . "\x2021;")
      ("Darr" . "\x21A1;")
      ("Dashv" . "\x2AE4;")
      ("Dcaron" . "\x10E;")
      ("Dcy" . "\x414;")
      ("Del" . "\x2207;")
      ("Delta" . "\x394;")
      ("Dfr" . "\x1D507;")
      ("DiacriticalAcute" . "\xB4;")
      ("DiacriticalDot" . "\x2D9;")
      ("DiacriticalDoubleAcute" . "\x2DD;")
      ("DiacriticalGrave" . "`")
      ("DiacriticalTilde" . "\x2DC;")
      ("Diamond" . "\x22C4;")
      ("DifferentialD" . "\x2146;")
      ("Dopf" . "\x1D53B;")
      ("Dot" . "\xA8;")
      ("DotDot" . "\x20DC;")
      ("DotEqual" . "\x2250;")
      ("DoubleContourIntegral" . "\x222F;")
      ("DoubleDot" . "\xA8;")
      ("DoubleDownArrow" . "\x21D3;")
      ("DoubleLeftArrow" . "\x21D0;")
      ("DoubleLeftRightArrow" . "\x21D4;")
      ("DoubleLeftTee" . "\x2AE4;")
      ("DoubleLongLeftArrow" . "\x27F8;")
      ("DoubleLongLeftRightArrow" . "\x27FA;")
      ("DoubleLongRightArrow" . "\x27F9;")
      ("DoubleRightArrow" . "\x21D2;")
      ("DoubleRightTee" . "\x22A8;")
      ("DoubleUpArrow" . "\x21D1;")
      ("DoubleUpDownArrow" . "\x21D5;")
      ("DoubleVerticalBar" . "\x2225;")
      ("DownArrow" . "\x2193;")
      ("DownArrowBar" . "\x2913;")
      ("DownArrowUpArrow" . "\x21F5;")
      ("DownBreve" . "\x311;")
      ("DownLeftRightVector" . "\x2950;")
      ("DownLeftTeeVector" . "\x295E;")
      ("DownLeftVector" . "\x21BD;")
      ("DownLeftVectorBar" . "\x2956;")
      ("DownRightTeeVector" . "\x295F;")
      ("DownRightVector" . "\x21C1;")
      ("DownRightVectorBar" . "\x2957;")
      ("DownTee" . "\x22A4;")
      ("DownTeeArrow" . "\x21A7;")
      ("Downarrow" . "\x21D3;")
      ("Dscr" . "\x1D49F;")
      ("Dstrok" . "\x110;")
      ("ENG" . "\x14A;")
      ("ETH" . "\xD0;")
      ("Eacute" . "\xC9;")
      ("Ecaron" . "\x11A;")
      ("Ecirc" . "\xCA;")
      ("Ecy" . "\x42D;")
      ("Edot" . "\x116;")
      ("Efr" . "\x1D508;")
      ("Egrave" . "\xC8;")
      ("Element" . "\x2208;")
      ("Emacr" . "\x112;")
      ("EmptySmallSquare" . "\x25FB;")
      ("EmptyVerySmallSquare" . "\x25AB;")
      ("Eogon" . "\x118;")
      ("Eopf" . "\x1D53C;")
      ("Epsilon" . "\x395;")
      ("Equal" . "\x2A75;")
      ("EqualTilde" . "\x2242;")
      ("Equilibrium" . "\x21CC;")
      ("Escr" . "\x2130;")
      ("Esim" . "\x2A73;")
      ("Eta" . "\x397;")
      ("Euml" . "\xCB;")
      ("Exists" . "\x2203;")
      ("ExponentialE" . "\x2147;")
      ("Fcy" . "\x424;")
      ("Ffr" . "\x1D509;")
      ("FilledSmallSquare" . "\x25FC;")
      ("FilledVerySmallSquare" . "\x25AA;")
      ("Fopf" . "\x1D53D;")
      ("ForAll" . "\x2200;")
      ("Fouriertrf" . "\x2131;")
      ("Fscr" . "\x2131;")
      ("GJcy" . "\x403;")
      ("GT" . ">")
      ("Gamma" . "\x393;")
      ("Gammad" . "\x3DC;")
      ("Gbreve" . "\x11E;")
      ("Gcedil" . "\x122;")
      ("Gcirc" . "\x11C;")
      ("Gcy" . "\x413;")
      ("Gdot" . "\x120;")
      ("Gfr" . "\x1D50A;")
      ("Gg" . "\x22D9;")
      ("Gopf" . "\x1D53E;")
      ("GreaterEqual" . "\x2265;")
      ("GreaterEqualLess" . "\x22DB;")
      ("GreaterFullEqual" . "\x2267;")
      ("GreaterGreater" . "\x2AA2;")
      ("GreaterLess" . "\x2277;")
      ("GreaterSlantEqual" . "\x2A7E;")
      ("GreaterTilde" . "\x2273;")
      ("Gscr" . "\x1D4A2;")
      ("Gt" . "\x226B;")
      ("HARDcy" . "\x42A;")
      ("Hacek" . "\x2C7;")
      ("Hat" . "^")
      ("Hcirc" . "\x124;")
      ("Hfr" . "\x210C;")
      ("HilbertSpace" . "\x210B;")
      ("Hopf" . "\x210D;")
      ("HorizontalLine" . "\x2500;")
      ("Hscr" . "\x210B;")
      ("Hstrok" . "\x126;")
      ("HumpDownHump" . "\x224E;")
      ("HumpEqual" . "\x224F;")
      ("IEcy" . "\x415;")
      ("IJlig" . "\x132;")
      ("IOcy" . "\x401;")
      ("Iacute" . "\xCD;")
      ("Icirc" . "\xCE;")
      ("Icy" . "\x418;")
      ("Idot" . "\x130;")
      ("Ifr" . "\x2111;")
      ("Igrave" . "\xCC;")
      ("Im" . "\x2111;")
      ("Imacr" . "\x12A;")
      ("ImaginaryI" . "\x2148;")
      ("Implies" . "\x21D2;")
      ("Int" . "\x222C;")
      ("Integral" . "\x222B;")
      ("Intersection" . "\x22C2;")
      ("InvisibleComma" . "\x2063;")
      ("InvisibleTimes" . "\x2062;")
      ("Iogon" . "\x12E;")
      ("Iopf" . "\x1D540;")
      ("Iota" . "\x399;")
      ("Iscr" . "\x2110;")
      ("Itilde" . "\x128;")
      ("Iukcy" . "\x406;")
      ("Iuml" . "\xCF;")
      ("Jcirc" . "\x134;")
      ("Jcy" . "\x419;")
      ("Jfr" . "\x1D50D;")
      ("Jopf" . "\x1D541;")
      ("Jscr" . "\x1D4A5;")
      ("Jsercy" . "\x408;")
      ("Jukcy" . "\x404;")
      ("KHcy" . "\x425;")
      ("KJcy" . "\x40C;")
      ("Kappa" . "\x39A;")
      ("Kcedil" . "\x136;")
      ("Kcy" . "\x41A;")
      ("Kfr" . "\x1D50E;")
      ("Kopf" . "\x1D542;")
      ("Kscr" . "\x1D4A6;")
      ("LJcy" . "\x409;")
      ("LT" . "<")
      ("Lacute" . "\x139;")
      ("Lambda" . "\x39B;")
      ("Lang" . "\x27EA;")
      ("Laplacetrf" . "\x2112;")
      ("Larr" . "\x219E;")
      ("Lcaron" . "\x13D;")
      ("Lcedil" . "\x13B;")
      ("Lcy" . "\x41B;")
      ("LeftAngleBracket" . "\x27E8;")
      ("LeftArrow" . "\x2190;")
      ("LeftArrowBar" . "\x21E4;")
      ("LeftArrowRightArrow" . "\x21C6;")
      ("LeftCeiling" . "\x2308;")
      ("LeftDoubleBracket" . "\x27E6;")
      ("LeftDownTeeVector" . "\x2961;")
      ("LeftDownVector" . "\x21C3;")
      ("LeftDownVectorBar" . "\x2959;")
      ("LeftFloor" . "\x230A;")
      ("LeftRightArrow" . "\x2194;")
      ("LeftRightVector" . "\x294E;")
      ("LeftTee" . "\x22A3;")
      ("LeftTeeArrow" . "\x21A4;")
      ("LeftTeeVector" . "\x295A;")
      ("LeftTriangle" . "\x22B2;")
      ("LeftTriangleBar" . "\x29CF;")
      ("LeftTriangleEqual" . "\x22B4;")
      ("LeftUpDownVector" . "\x2951;")
      ("LeftUpTeeVector" . "\x2960;")
      ("LeftUpVector" . "\x21BF;")
      ("LeftUpVectorBar" . "\x2958;")
      ("LeftVector" . "\x21BC;")
      ("LeftVectorBar" . "\x2952;")
      ("Leftarrow" . "\x21D0;")
      ("Leftrightarrow" . "\x21D4;")
      ("LessEqualGreater" . "\x22DA;")
      ("LessFullEqual" . "\x2266;")
      ("LessGreater" . "\x2276;")
      ("LessLess" . "\x2AA1;")
      ("LessSlantEqual" . "\x2A7D;")
      ("LessTilde" . "\x2272;")
      ("Lfr" . "\x1D50F;")
      ("Ll" . "\x22D8;")
      ("Lleftarrow" . "\x21DA;")
      ("Lmidot" . "\x13F;")
      ("LongLeftArrow" . "\x27F5;")
      ("LongLeftRightArrow" . "\x27F7;")
      ("LongRightArrow" . "\x27F6;")
      ("Longleftarrow" . "\x27F8;")
      ("Longleftrightarrow" . "\x27FA;")
      ("Longrightarrow" . "\x27F9;")
      ("Lopf" . "\x1D543;")
      ("LowerLeftArrow" . "\x2199;")
      ("LowerRightArrow" . "\x2198;")
      ("Lscr" . "\x2112;")
      ("Lsh" . "\x21B0;")
      ("Lstrok" . "\x141;")
      ("Lt" . "\x226A;")
      ("Map" . "\x2905;")
      ("Mcy" . "\x41C;")
      ("MediumSpace" . "\x205F;")
      ("Mellintrf" . "\x2133;")
      ("Mfr" . "\x1D510;")
      ("MinusPlus" . "\x2213;")
      ("Mopf" . "\x1D544;")
      ("Mscr" . "\x2133;")
      ("Mu" . "\x39C;")
      ("NJcy" . "\x40A;")
      ("Nacute" . "\x143;")
      ("Ncaron" . "\x147;")
      ("Ncedil" . "\x145;")
      ("Ncy" . "\x41D;")
      ("NegativeMediumSpace" . "\x200B;")
      ("NegativeThickSpace" . "\x200B;")
      ("NegativeThinSpace" . "\x200B;")
      ("NegativeVeryThinSpace" . "\x200B;")
      ("NestedGreaterGreater" . "\x226B;")
      ("NestedLessLess" . "\x226A;")
      ("NewLine" . "\xA;")
      ("Nfr" . "\x1D511;")
      ("NoBreak" . "\x2060;")
      ("NonBreakingSpace" . "\xA0;")
      ("Nopf" . "\x2115;")
      ("Not" . "\x2AEC;")
      ("NotCongruent" . "\x2262;")
      ("NotCupCap" . "\x226D;")
      ("NotDoubleVerticalBar" . "\x2226;")
      ("NotElement" . "\x2209;")
      ("NotEqual" . "\x2260;")
      ("NotEqualTilde" . "\x2242;\x338;")
      ("NotExists" . "\x2204;")
      ("NotGreater" . "\x226F;")
      ("NotGreaterEqual" . "\x2271;")
      ("NotGreaterFullEqual" . "\x2267;\x338;")
      ("NotGreaterGreater" . "\x226B;\x338;")
      ("NotGreaterLess" . "\x2279;")
      ("NotGreaterSlantEqual" . "\x2A7E;\x338;")
      ("NotGreaterTilde" . "\x2275;")
      ("NotHumpDownHump" . "\x224E;\x338;")
      ("NotHumpEqual" . "\x224F;\x338;")
      ("NotLeftTriangle" . "\x22EA;")
      ("NotLeftTriangleBar" . "\x29CF;\x338;")
      ("NotLeftTriangleEqual" . "\x22EC;")
      ("NotLess" . "\x226E;")
      ("NotLessEqual" . "\x2270;")
      ("NotLessGreater" . "\x2278;")
      ("NotLessLess" . "\x226A;\x338;")
      ("NotLessSlantEqual" . "\x2A7D;\x338;")
      ("NotLessTilde" . "\x2274;")
      ("NotNestedGreaterGreater" . "\x2AA2;\x338;")
      ("NotNestedLessLess" . "\x2AA1;\x338;")
      ("NotPrecedes" . "\x2280;")
      ("NotPrecedesEqual" . "\x2AAF;\x338;")
      ("NotPrecedesSlantEqual" . "\x22E0;")
      ("NotReverseElement" . "\x220C;")
      ("NotRightTriangle" . "\x22EB;")
      ("NotRightTriangleBar" . "\x29D0;\x338;")
      ("NotRightTriangleEqual" . "\x22ED;")
      ("NotSquareSubset" . "\x228F;\x338;")
      ("NotSquareSubsetEqual" . "\x22E2;")
      ("NotSquareSuperset" . "\x2290;\x338;")
      ("NotSquareSupersetEqual" . "\x22E3;")
      ("NotSubset" . "\x2282;\x20D2;")
      ("NotSubsetEqual" . "\x2288;")
      ("NotSucceeds" . "\x2281;")
      ("NotSucceedsEqual" . "\x2AB0;\x338;")
      ("NotSucceedsSlantEqual" . "\x22E1;")
      ("NotSucceedsTilde" . "\x227F;\x338;")
      ("NotSuperset" . "\x2283;\x20D2;")
      ("NotSupersetEqual" . "\x2289;")
      ("NotTilde" . "\x2241;")
      ("NotTildeEqual" . "\x2244;")
      ("NotTildeFullEqual" . "\x2247;")
      ("NotTildeTilde" . "\x2249;")
      ("NotVerticalBar" . "\x2224;")
      ("Nscr" . "\x1D4A9;")
      ("Ntilde" . "\xD1;")
      ("Nu" . "\x39D;")
      ("OElig" . "\x152;")
      ("Oacute" . "\xD3;")
      ("Ocirc" . "\xD4;")
      ("Ocy" . "\x41E;")
      ("Odblac" . "\x150;")
      ("Ofr" . "\x1D512;")
      ("Ograve" . "\xD2;")
      ("Omacr" . "\x14C;")
      ("Omega" . "\x3A9;")
      ("Omicron" . "\x39F;")
      ("Oopf" . "\x1D546;")
      ("OpenCurlyDoubleQuote" . "\x201C;")
      ("OpenCurlyQuote" . "\x2018;")
      ("Or" . "\x2A54;")
      ("Oscr" . "\x1D4AA;")
      ("Oslash" . "\xD8;")
      ("Otilde" . "\xD5;")
      ("Otimes" . "\x2A37;")
      ("Ouml" . "\xD6;")
      ("OverBar" . "\x203E;")
      ("OverBrace" . "\x23DE;")
      ("OverBracket" . "\x23B4;")
      ("OverParenthesis" . "\x23DC;")
      ("PartialD" . "\x2202;")
      ("Pcy" . "\x41F;")
      ("Pfr" . "\x1D513;")
      ("Phi" . "\x3A6;")
      ("Pi" . "\x3A0;")
      ("PlusMinus" . "\xB1;")
      ("Poincareplane" . "\x210C;")
      ("Popf" . "\x2119;")
      ("Pr" . "\x2ABB;")
      ("Precedes" . "\x227A;")
      ("PrecedesEqual" . "\x2AAF;")
      ("PrecedesSlantEqual" . "\x227C;")
      ("PrecedesTilde" . "\x227E;")
      ("Prime" . "\x2033;")
      ("Product" . "\x220F;")
      ("Proportion" . "\x2237;")
      ("Proportional" . "\x221D;")
      ("Pscr" . "\x1D4AB;")
      ("Psi" . "\x3A8;")
      ("QUOT" . "\"")
      ("Qfr" . "\x1D514;")
      ("Qopf" . "\x211A;")
      ("Qscr" . "\x1D4AC;")
      ("RBarr" . "\x2910;")
      ("REG" . "\xAE;")
      ("Racute" . "\x154;")
      ("Rang" . "\x27EB;")
      ("Rarr" . "\x21A0;")
      ("Rarrtl" . "\x2916;")
      ("Rcaron" . "\x158;")
      ("Rcedil" . "\x156;")
      ("Rcy" . "\x420;")
      ("Re" . "\x211C;")
      ("ReverseElement" . "\x220B;")
      ("ReverseEquilibrium" . "\x21CB;")
      ("ReverseUpEquilibrium" . "\x296F;")
      ("Rfr" . "\x211C;")
      ("Rho" . "\x3A1;")
      ("RightAngleBracket" . "\x27E9;")
      ("RightArrow" . "\x2192;")
      ("RightArrowBar" . "\x21E5;")
      ("RightArrowLeftArrow" . "\x21C4;")
      ("RightCeiling" . "\x2309;")
      ("RightDoubleBracket" . "\x27E7;")
      ("RightDownTeeVector" . "\x295D;")
      ("RightDownVector" . "\x21C2;")
      ("RightDownVectorBar" . "\x2955;")
      ("RightFloor" . "\x230B;")
      ("RightTee" . "\x22A2;")
      ("RightTeeArrow" . "\x21A6;")
      ("RightTeeVector" . "\x295B;")
      ("RightTriangle" . "\x22B3;")
      ("RightTriangleBar" . "\x29D0;")
      ("RightTriangleEqual" . "\x22B5;")
      ("RightUpDownVector" . "\x294F;")
      ("RightUpTeeVector" . "\x295C;")
      ("RightUpVector" . "\x21BE;")
      ("RightUpVectorBar" . "\x2954;")
      ("RightVector" . "\x21C0;")
      ("RightVectorBar" . "\x2953;")
      ("Rightarrow" . "\x21D2;")
      ("Ropf" . "\x211D;")
      ("RoundImplies" . "\x2970;")
      ("Rrightarrow" . "\x21DB;")
      ("Rscr" . "\x211B;")
      ("Rsh" . "\x21B1;")
      ("RuleDelayed" . "\x29F4;")
      ("SHCHcy" . "\x429;")
      ("SHcy" . "\x428;")
      ("SOFTcy" . "\x42C;")
      ("Sacute" . "\x15A;")
      ("Sc" . "\x2ABC;")
      ("Scaron" . "\x160;")
      ("Scedil" . "\x15E;")
      ("Scirc" . "\x15C;")
      ("Scy" . "\x421;")
      ("Sfr" . "\x1D516;")
      ("ShortDownArrow" . "\x2193;")
      ("ShortLeftArrow" . "\x2190;")
      ("ShortRightArrow" . "\x2192;")
      ("ShortUpArrow" . "\x2191;")
      ("Sigma" . "\x3A3;")
      ("SmallCircle" . "\x2218;")
      ("Sopf" . "\x1D54A;")
      ("Sqrt" . "\x221A;")
      ("Square" . "\x25A1;")
      ("SquareIntersection" . "\x2293;")
      ("SquareSubset" . "\x228F;")
      ("SquareSubsetEqual" . "\x2291;")
      ("SquareSuperset" . "\x2290;")
      ("SquareSupersetEqual" . "\x2292;")
      ("SquareUnion" . "\x2294;")
      ("Sscr" . "\x1D4AE;")
      ("Star" . "\x22C6;")
      ("Sub" . "\x22D0;")
      ("Subset" . "\x22D0;")
      ("SubsetEqual" . "\x2286;")
      ("Succeeds" . "\x227B;")
      ("SucceedsEqual" . "\x2AB0;")
      ("SucceedsSlantEqual" . "\x227D;")
      ("SucceedsTilde" . "\x227F;")
      ("SuchThat" . "\x220B;")
      ("Sum" . "\x2211;")
      ("Sup" . "\x22D1;")
      ("Superset" . "\x2283;")
      ("SupersetEqual" . "\x2287;")
      ("Supset" . "\x22D1;")
      ("THORN" . "\xDE;")
      ("TRADE" . "\x2122;")
      ("TSHcy" . "\x40B;")
      ("TScy" . "\x426;")
      ("Tab" . "\x9;")
      ("Tau" . "\x3A4;")
      ("Tcaron" . "\x164;")
      ("Tcedil" . "\x162;")
      ("Tcy" . "\x422;")
      ("Tfr" . "\x1D517;")
      ("Therefore" . "\x2234;")
      ("Theta" . "\x398;")
      ("ThickSpace" . "\x205F;\x200A;")
      ("ThinSpace" . "\x2009;")
      ("Tilde" . "\x223C;")
      ("TildeEqual" . "\x2243;")
      ("TildeFullEqual" . "\x2245;")
      ("TildeTilde" . "\x2248;")
      ("Topf" . "\x1D54B;")
      ("TripleDot" . "\x20DB;")
      ("Tscr" . "\x1D4AF;")
      ("Tstrok" . "\x166;")
      ("Uacute" . "\xDA;")
      ("Uarr" . "\x219F;")
      ("Uarrocir" . "\x2949;")
      ("Ubrcy" . "\x40E;")
      ("Ubreve" . "\x16C;")
      ("Ucirc" . "\xDB;")
      ("Ucy" . "\x423;")
      ("Udblac" . "\x170;")
      ("Ufr" . "\x1D518;")
      ("Ugrave" . "\xD9;")
      ("Umacr" . "\x16A;")
      ("UnderBar" . "_")
      ("UnderBrace" . "\x23DF;")
      ("UnderBracket" . "\x23B5;")
      ("UnderParenthesis" . "\x23DD;")
      ("Union" . "\x22C3;")
      ("UnionPlus" . "\x228E;")
      ("Uogon" . "\x172;")
      ("Uopf" . "\x1D54C;")
      ("UpArrow" . "\x2191;")
      ("UpArrowBar" . "\x2912;")
      ("UpArrowDownArrow" . "\x21C5;")
      ("UpDownArrow" . "\x2195;")
      ("UpEquilibrium" . "\x296E;")
      ("UpTee" . "\x22A5;")
      ("UpTeeArrow" . "\x21A5;")
      ("Uparrow" . "\x21D1;")
      ("Updownarrow" . "\x21D5;")
      ("UpperLeftArrow" . "\x2196;")
      ("UpperRightArrow" . "\x2197;")
      ("Upsi" . "\x3D2;")
      ("Upsilon" . "\x3A5;")
      ("Uring" . "\x16E;")
      ("Uscr" . "\x1D4B0;")
      ("Utilde" . "\x168;")
      ("Uuml" . "\xDC;")
      ("VDash" . "\x22AB;")
      ("Vbar" . "\x2AEB;")
      ("Vcy" . "\x412;")
      ("Vdash" . "\x22A9;")
      ("Vdashl" . "\x2AE6;")
      ("Vee" . "\x22C1;")
      ("Verbar" . "\x2016;")
      ("Vert" . "\x2016;")
      ("VerticalBar" . "\x2223;")
      ("VerticalLine" . "|")
      ("VerticalSeparator" . "\x2758;")
      ("VerticalTilde" . "\x2240;")
      ("VeryThinSpace" . "\x200A;")
      ("Vfr" . "\x1D519;")
      ("Vopf" . "\x1D54D;")
      ("Vscr" . "\x1D4B1;")
      ("Vvdash" . "\x22AA;")
      ("Wcirc" . "\x174;")
      ("Wedge" . "\x22C0;")
      ("Wfr" . "\x1D51A;")
      ("Wopf" . "\x1D54E;")
      ("Wscr" . "\x1D4B2;")
      ("Xfr" . "\x1D51B;")
      ("Xi" . "\x39E;")
      ("Xopf" . "\x1D54F;")
      ("Xscr" . "\x1D4B3;")
      ("YAcy" . "\x42F;")
      ("YIcy" . "\x407;")
      ("YUcy" . "\x42E;")
      ("Yacute" . "\xDD;")
      ("Ycirc" . "\x176;")
      ("Ycy" . "\x42B;")
      ("Yfr" . "\x1D51C;")
      ("Yopf" . "\x1D550;")
      ("Yscr" . "\x1D4B4;")
      ("Yuml" . "\x178;")
      ("ZHcy" . "\x416;")
      ("Zacute" . "\x179;")
      ("Zcaron" . "\x17D;")
      ("Zcy" . "\x417;")
      ("Zdot" . "\x17B;")
      ("ZeroWidthSpace" . "\x200B;")
      ("Zeta" . "\x396;")
      ("Zfr" . "\x2128;")
      ("Zopf" . "\x2124;")
      ("Zscr" . "\x1D4B5;")
      ("aacute" . "\xE1;")
      ("abreve" . "\x103;")
      ("ac" . "\x223E;")
      ("acE" . "\x223E;\x333;")
      ("acd" . "\x223F;")
      ("acirc" . "\xE2;")
      ("acute" . "\xB4;")
      ("acy" . "\x430;")
      ("aelig" . "\xE6;")
      ("af" . "\x2061;")
      ("afr" . "\x1D51E;")
      ("agrave" . "\xE0;")
      ("alefsym" . "\x2135;")
      ("aleph" . "\x2135;")
      ("alpha" . "\x3B1;")
      ("amacr" . "\x101;")
      ("amalg" . "\x2A3F;")
      ("amp" . "&")
      ("and" . "\x2227;")
      ("andand" . "\x2A55;")
      ("andd" . "\x2A5C;")
      ("andslope" . "\x2A58;")
      ("andv" . "\x2A5A;")
      ("ang" . "\x2220;")
      ("ange" . "\x29A4;")
      ("angle" . "\x2220;")
      ("angmsd" . "\x2221;")
      ("angmsdaa" . "\x29A8;")
      ("angmsdab" . "\x29A9;")
      ("angmsdac" . "\x29AA;")
      ("angmsdad" . "\x29AB;")
      ("angmsdae" . "\x29AC;")
      ("angmsdaf" . "\x29AD;")
      ("angmsdag" . "\x29AE;")
      ("angmsdah" . "\x29AF;")
      ("angrt" . "\x221F;")
      ("angrtvb" . "\x22BE;")
      ("angrtvbd" . "\x299D;")
      ("angsph" . "\x2222;")
      ("angst" . "\xC5;")
      ("angzarr" . "\x237C;")
      ("aogon" . "\x105;")
      ("aopf" . "\x1D552;")
      ("ap" . "\x2248;")
      ("apE" . "\x2A70;")
      ("apacir" . "\x2A6F;")
      ("ape" . "\x224A;")
      ("apid" . "\x224B;")
      ("apos" . "'")
      ("approx" . "\x2248;")
      ("approxeq" . "\x224A;")
      ("aring" . "\xE5;")
      ("ascr" . "\x1D4B6;")
      ("ast" . "*")
      ("asymp" . "\x2248;")
      ("asympeq" . "\x224D;")
      ("atilde" . "\xE3;")
      ("auml" . "\xE4;")
      ("awconint" . "\x2233;")
      ("awint" . "\x2A11;")
      ("bNot" . "\x2AED;")
      ("backcong" . "\x224C;")
      ("backepsilon" . "\x3F6;")
      ("backprime" . "\x2035;")
      ("backsim" . "\x223D;")
      ("backsimeq" . "\x22CD;")
      ("barvee" . "\x22BD;")
      ("barwed" . "\x2305;")
      ("barwedge" . "\x2305;")
      ("bbrk" . "\x23B5;")
      ("bbrktbrk" . "\x23B6;")
      ("bcong" . "\x224C;")
      ("bcy" . "\x431;")
      ("bdquo" . "\x201E;")
      ("becaus" . "\x2235;")
      ("because" . "\x2235;")
      ("bemptyv" . "\x29B0;")
      ("bepsi" . "\x3F6;")
      ("bernou" . "\x212C;")
      ("beta" . "\x3B2;")
      ("beth" . "\x2136;")
      ("between" . "\x226C;")
      ("bfr" . "\x1D51F;")
      ("bigcap" . "\x22C2;")
      ("bigcirc" . "\x25EF;")
      ("bigcup" . "\x22C3;")
      ("bigodot" . "\x2A00;")
      ("bigoplus" . "\x2A01;")
      ("bigotimes" . "\x2A02;")
      ("bigsqcup" . "\x2A06;")
      ("bigstar" . "\x2605;")
      ("bigtriangledown" . "\x25BD;")
      ("bigtriangleup" . "\x25B3;")
      ("biguplus" . "\x2A04;")
      ("bigvee" . "\x22C1;")
      ("bigwedge" . "\x22C0;")
      ("bkarow" . "\x290D;")
      ("blacklozenge" . "\x29EB;")
      ("blacksquare" . "\x25AA;")
      ("blacktriangle" . "\x25B4;")
      ("blacktriangledown" . "\x25BE;")
      ("blacktriangleleft" . "\x25C2;")
      ("blacktriangleright" . "\x25B8;")
      ("blank" . "\x2423;")
      ("blk12" . "\x2592;")
      ("blk14" . "\x2591;")
      ("blk34" . "\x2593;")
      ("block" . "\x2588;")
      ("bne" . "=\x20E5;")
      ("bnequiv" . "\x2261;\x20E5;")
      ("bnot" . "\x2310;")
      ("bopf" . "\x1D553;")
      ("bot" . "\x22A5;")
      ("bottom" . "\x22A5;")
      ("bowtie" . "\x22C8;")
      ("boxDL" . "\x2557;")
      ("boxDR" . "\x2554;")
      ("boxDl" . "\x2556;")
      ("boxDr" . "\x2553;")
      ("boxH" . "\x2550;")
      ("boxHD" . "\x2566;")
      ("boxHU" . "\x2569;")
      ("boxHd" . "\x2564;")
      ("boxHu" . "\x2567;")
      ("boxUL" . "\x255D;")
      ("boxUR" . "\x255A;")
      ("boxUl" . "\x255C;")
      ("boxUr" . "\x2559;")
      ("boxV" . "\x2551;")
      ("boxVH" . "\x256C;")
      ("boxVL" . "\x2563;")
      ("boxVR" . "\x2560;")
      ("boxVh" . "\x256B;")
      ("boxVl" . "\x2562;")
      ("boxVr" . "\x255F;")
      ("boxbox" . "\x29C9;")
      ("boxdL" . "\x2555;")
      ("boxdR" . "\x2552;")
      ("boxdl" . "\x2510;")
      ("boxdr" . "\x250C;")
      ("boxh" . "\x2500;")
      ("boxhD" . "\x2565;")
      ("boxhU" . "\x2568;")
      ("boxhd" . "\x252C;")
      ("boxhu" . "\x2534;")
      ("boxminus" . "\x229F;")
      ("boxplus" . "\x229E;")
      ("boxtimes" . "\x22A0;")
      ("boxuL" . "\x255B;")
      ("boxuR" . "\x2558;")
      ("boxul" . "\x2518;")
      ("boxur" . "\x2514;")
      ("boxv" . "\x2502;")
      ("boxvH" . "\x256A;")
      ("boxvL" . "\x2561;")
      ("boxvR" . "\x255E;")
      ("boxvh" . "\x253C;")
      ("boxvl" . "\x2524;")
      ("boxvr" . "\x251C;")
      ("bprime" . "\x2035;")
      ("breve" . "\x2D8;")
      ("brvbar" . "\xA6;")
      ("bscr" . "\x1D4B7;")
      ("bsemi" . "\x204F;")
      ("bsim" . "\x223D;")
      ("bsime" . "\x22CD;")
      ("bsol" . "\\")
      ("bsolb" . "\x29C5;")
      ("bsolhsub" . "\x27C8;")
      ("bull" . "\x2022;")
      ("bullet" . "\x2022;")
      ("bump" . "\x224E;")
      ("bumpE" . "\x2AAE;")
      ("bumpe" . "\x224F;")
      ("bumpeq" . "\x224F;")
      ("cacute" . "\x107;")
      ("cap" . "\x2229;")
      ("capand" . "\x2A44;")
      ("capbrcup" . "\x2A49;")
      ("capcap" . "\x2A4B;")
      ("capcup" . "\x2A47;")
      ("capdot" . "\x2A40;")
      ("caps" . "\x2229;\xFE00;")
      ("caret" . "\x2041;")
      ("caron" . "\x2C7;")
      ("ccaps" . "\x2A4D;")
      ("ccaron" . "\x10D;")
      ("ccedil" . "\xE7;")
      ("ccirc" . "\x109;")
      ("ccups" . "\x2A4C;")
      ("ccupssm" . "\x2A50;")
      ("cdot" . "\x10B;")
      ("cedil" . "\xB8;")
      ("cemptyv" . "\x29B2;")
      ("cent" . "\xA2;")
      ("centerdot" . "\xB7;")
      ("cfr" . "\x1D520;")
      ("chcy" . "\x447;")
      ("check" . "\x2713;")
      ("checkmark" . "\x2713;")
      ("chi" . "\x3C7;")
      ("cir" . "\x25CB;")
      ("cirE" . "\x29C3;")
      ("circ" . "\x2C6;")
      ("circeq" . "\x2257;")
      ("circlearrowleft" . "\x21BA;")
      ("circlearrowright" . "\x21BB;")
      ("circledR" . "\xAE;")
      ("circledS" . "\x24C8;")
      ("circledast" . "\x229B;")
      ("circledcirc" . "\x229A;")
      ("circleddash" . "\x229D;")
      ("cire" . "\x2257;")
      ("cirfnint" . "\x2A10;")
      ("cirmid" . "\x2AEF;")
      ("cirscir" . "\x29C2;")
      ("clubs" . "\x2663;")
      ("clubsuit" . "\x2663;")
      ("colon" . ":")
      ("colone" . "\x2254;")
      ("coloneq" . "\x2254;")
      ("comma" . ",")
      ("commat" . "@")
      ("comp" . "\x2201;")
      ("compfn" . "\x2218;")
      ("complement" . "\x2201;")
      ("complexes" . "\x2102;")
      ("cong" . "\x2245;")
      ("congdot" . "\x2A6D;")
      ("conint" . "\x222E;")
      ("copf" . "\x1D554;")
      ("coprod" . "\x2210;")
      ("copy" . "\xA9;")
      ("copysr" . "\x2117;")
      ("crarr" . "\x21B5;")
      ("cross" . "\x2717;")
      ("cscr" . "\x1D4B8;")
      ("csub" . "\x2ACF;")
      ("csube" . "\x2AD1;")
      ("csup" . "\x2AD0;")
      ("csupe" . "\x2AD2;")
      ("ctdot" . "\x22EF;")
      ("cudarrl" . "\x2938;")
      ("cudarrr" . "\x2935;")
      ("cuepr" . "\x22DE;")
      ("cuesc" . "\x22DF;")
      ("cularr" . "\x21B6;")
      ("cularrp" . "\x293D;")
      ("cup" . "\x222A;")
      ("cupbrcap" . "\x2A48;")
      ("cupcap" . "\x2A46;")
      ("cupcup" . "\x2A4A;")
      ("cupdot" . "\x228D;")
      ("cupor" . "\x2A45;")
      ("cups" . "\x222A;\xFE00;")
      ("curarr" . "\x21B7;")
      ("curarrm" . "\x293C;")
      ("curlyeqprec" . "\x22DE;")
      ("curlyeqsucc" . "\x22DF;")
      ("curlyvee" . "\x22CE;")
      ("curlywedge" . "\x22CF;")
      ("curren" . "\xA4;")
      ("curvearrowleft" . "\x21B6;")
      ("curvearrowright" . "\x21B7;")
      ("cuvee" . "\x22CE;")
      ("cuwed" . "\x22CF;")
      ("cwconint" . "\x2232;")
      ("cwint" . "\x2231;")
      ("cylcty" . "\x232D;")
      ("dArr" . "\x21D3;")
      ("dHar" . "\x2965;")
      ("dagger" . "\x2020;")
      ("daleth" . "\x2138;")
      ("darr" . "\x2193;")
      ("dash" . "\x2010;")
      ("dashv" . "\x22A3;")
      ("dbkarow" . "\x290F;")
      ("dblac" . "\x2DD;")
      ("dcaron" . "\x10F;")
      ("dcy" . "\x434;")
      ("dd" . "\x2146;")
      ("ddagger" . "\x2021;")
      ("ddarr" . "\x21CA;")
      ("ddotseq" . "\x2A77;")
      ("deg" . "\xB0;")
      ("delta" . "\x3B4;")
      ("demptyv" . "\x29B1;")
      ("dfisht" . "\x297F;")
      ("dfr" . "\x1D521;")
      ("dharl" . "\x21C3;")
      ("dharr" . "\x21C2;")
      ("diam" . "\x22C4;")
      ("diamond" . "\x22C4;")
      ("diamondsuit" . "\x2666;")
      ("diams" . "\x2666;")
      ("die" . "\xA8;")
      ("digamma" . "\x3DD;")
      ("disin" . "\x22F2;")
      ("div" . "\xF7;")
      ("divide" . "\xF7;")
      ("divideontimes" . "\x22C7;")
      ("divonx" . "\x22C7;")
      ("djcy" . "\x452;")
      ("dlcorn" . "\x231E;")
      ("dlcrop" . "\x230D;")
      ("dollar" . "$")
      ("dopf" . "\x1D555;")
      ("dot" . "\x2D9;")
      ("doteq" . "\x2250;")
      ("doteqdot" . "\x2251;")
      ("dotminus" . "\x2238;")
      ("dotplus" . "\x2214;")
      ("dotsquare" . "\x22A1;")
      ("doublebarwedge" . "\x2306;")
      ("downarrow" . "\x2193;")
      ("downdownarrows" . "\x21CA;")
      ("downharpoonleft" . "\x21C3;")
      ("downharpoonright" . "\x21C2;")
      ("drbkarow" . "\x2910;")
      ("drcorn" . "\x231F;")
      ("drcrop" . "\x230C;")
      ("dscr" . "\x1D4B9;")
      ("dscy" . "\x455;")
      ("dsol" . "\x29F6;")
      ("dstrok" . "\x111;")
      ("dtdot" . "\x22F1;")
      ("dtri" . "\x25BF;")
      ("dtrif" . "\x25BE;")
      ("duarr" . "\x21F5;")
      ("duhar" . "\x296F;")
      ("dwangle" . "\x29A6;")
      ("dzcy" . "\x45F;")
      ("dzigrarr" . "\x27FF;")
      ("eDDot" . "\x2A77;")
      ("eDot" . "\x2251;")
      ("eacute" . "\xE9;")
      ("easter" . "\x2A6E;")
      ("ecaron" . "\x11B;")
      ("ecir" . "\x2256;")
      ("ecirc" . "\xEA;")
      ("ecolon" . "\x2255;")
      ("ecy" . "\x44D;")
      ("edot" . "\x117;")
      ("ee" . "\x2147;")
      ("efDot" . "\x2252;")
      ("efr" . "\x1D522;")
      ("eg" . "\x2A9A;")
      ("egrave" . "\xE8;")
      ("egs" . "\x2A96;")
      ("egsdot" . "\x2A98;")
      ("el" . "\x2A99;")
      ("elinters" . "\x23E7;")
      ("ell" . "\x2113;")
      ("els" . "\x2A95;")
      ("elsdot" . "\x2A97;")
      ("emacr" . "\x113;")
      ("empty" . "\x2205;")
      ("emptyset" . "\x2205;")
      ("emptyv" . "\x2205;")
      ("emsp" . "\x2003;")
      ("emsp13" . "\x2004;")
      ("emsp14" . "\x2005;")
      ("eng" . "\x14B;")
      ("ensp" . "\x2002;")
      ("eogon" . "\x119;")
      ("eopf" . "\x1D556;")
      ("epar" . "\x22D5;")
      ("eparsl" . "\x29E3;")
      ("eplus" . "\x2A71;")
      ("epsi" . "\x3B5;")
      ("epsilon" . "\x3B5;")
      ("epsiv" . "\x3F5;")
      ("eqcirc" . "\x2256;")
      ("eqcolon" . "\x2255;")
      ("eqsim" . "\x2242;")
      ("eqslantgtr" . "\x2A96;")
      ("eqslantless" . "\x2A95;")
      ("equals" . "=")
      ("equest" . "\x225F;")
      ("equiv" . "\x2261;")
      ("equivDD" . "\x2A78;")
      ("eqvparsl" . "\x29E5;")
      ("erDot" . "\x2253;")
      ("erarr" . "\x2971;")
      ("escr" . "\x212F;")
      ("esdot" . "\x2250;")
      ("esim" . "\x2242;")
      ("eta" . "\x3B7;")
      ("eth" . "\xF0;")
      ("euml" . "\xEB;")
      ("euro" . "\x20AC;")
      ("excl" . "!")
      ("exist" . "\x2203;")
      ("expectation" . "\x2130;")
      ("exponentiale" . "\x2147;")
      ("fallingdotseq" . "\x2252;")
      ("fcy" . "\x444;")
      ("female" . "\x2640;")
      ("ffilig" . "\xFB03;")
      ("fflig" . "\xFB00;")
      ("ffllig" . "\xFB04;")
      ("ffr" . "\x1D523;")
      ("filig" . "\xFB01;")
      ("fjlig" . "fj")
      ("flat" . "\x266D;")
      ("fllig" . "\xFB02;")
      ("fltns" . "\x25B1;")
      ("fnof" . "\x192;")
      ("fopf" . "\x1D557;")
      ("forall" . "\x2200;")
      ("fork" . "\x22D4;")
      ("forkv" . "\x2AD9;")
      ("fpartint" . "\x2A0D;")
      ("frac12" . "\xBD;")
      ("frac13" . "\x2153;")
      ("frac14" . "\xBC;")
      ("frac15" . "\x2155;")
      ("frac16" . "\x2159;")
      ("frac18" . "\x215B;")
      ("frac23" . "\x2154;")
      ("frac25" . "\x2156;")
      ("frac34" . "\xBE;")
      ("frac35" . "\x2157;")
      ("frac38" . "\x215C;")
      ("frac45" . "\x2158;")
      ("frac56" . "\x215A;")
      ("frac58" . "\x215D;")
      ("frac78" . "\x215E;")
      ("frasl" . "\x2044;")
      ("frown" . "\x2322;")
      ("fscr" . "\x1D4BB;")
      ("gE" . "\x2267;")
      ("gEl" . "\x2A8C;")
      ("gacute" . "\x1F5;")
      ("gamma" . "\x3B3;")
      ("gammad" . "\x3DD;")
      ("gap" . "\x2A86;")
      ("gbreve" . "\x11F;")
      ("gcirc" . "\x11D;")
      ("gcy" . "\x433;")
      ("gdot" . "\x121;")
      ("ge" . "\x2265;")
      ("gel" . "\x22DB;")
      ("geq" . "\x2265;")
      ("geqq" . "\x2267;")
      ("geqslant" . "\x2A7E;")
      ("ges" . "\x2A7E;")
      ("gescc" . "\x2AA9;")
      ("gesdot" . "\x2A80;")
      ("gesdoto" . "\x2A82;")
      ("gesdotol" . "\x2A84;")
      ("gesl" . "\x22DB;\xFE00;")
      ("gesles" . "\x2A94;")
      ("gfr" . "\x1D524;")
      ("gg" . "\x226B;")
      ("ggg" . "\x22D9;")
      ("gimel" . "\x2137;")
      ("gjcy" . "\x453;")
      ("gl" . "\x2277;")
      ("glE" . "\x2A92;")
      ("gla" . "\x2AA5;")
      ("glj" . "\x2AA4;")
      ("gnE" . "\x2269;")
      ("gnap" . "\x2A8A;")
      ("gnapprox" . "\x2A8A;")
      ("gne" . "\x2A88;")
      ("gneq" . "\x2A88;")
      ("gneqq" . "\x2269;")
      ("gnsim" . "\x22E7;")
      ("gopf" . "\x1D558;")
      ("grave" . "`")
      ("gscr" . "\x210A;")
      ("gsim" . "\x2273;")
      ("gsime" . "\x2A8E;")
      ("gsiml" . "\x2A90;")
      ("gt" . ">")
      ("gtcc" . "\x2AA7;")
      ("gtcir" . "\x2A7A;")
      ("gtdot" . "\x22D7;")
      ("gtlPar" . "\x2995;")
      ("gtquest" . "\x2A7C;")
      ("gtrapprox" . "\x2A86;")
      ("gtrarr" . "\x2978;")
      ("gtrdot" . "\x22D7;")
      ("gtreqless" . "\x22DB;")
      ("gtreqqless" . "\x2A8C;")
      ("gtrless" . "\x2277;")
      ("gtrsim" . "\x2273;")
      ("gvertneqq" . "\x2269;\xFE00;")
      ("gvnE" . "\x2269;\xFE00;")
      ("hArr" . "\x21D4;")
      ("hairsp" . "\x200A;")
      ("half" . "\xBD;")
      ("hamilt" . "\x210B;")
      ("hardcy" . "\x44A;")
      ("harr" . "\x2194;")
      ("harrcir" . "\x2948;")
      ("harrw" . "\x21AD;")
      ("hbar" . "\x210F;")
      ("hcirc" . "\x125;")
      ("hearts" . "\x2665;")
      ("heartsuit" . "\x2665;")
      ("hellip" . "\x2026;")
      ("hercon" . "\x22B9;")
      ("hfr" . "\x1D525;")
      ("hksearow" . "\x2925;")
      ("hkswarow" . "\x2926;")
      ("hoarr" . "\x21FF;")
      ("homtht" . "\x223B;")
      ("hookleftarrow" . "\x21A9;")
      ("hookrightarrow" . "\x21AA;")
      ("hopf" . "\x1D559;")
      ("horbar" . "\x2015;")
      ("hscr" . "\x1D4BD;")
      ("hslash" . "\x210F;")
      ("hstrok" . "\x127;")
      ("hybull" . "\x2043;")
      ("hyphen" . "\x2010;")
      ("iacute" . "\xED;")
      ("ic" . "\x2063;")
      ("icirc" . "\xEE;")
      ("icy" . "\x438;")
      ("iecy" . "\x435;")
      ("iexcl" . "\xA1;")
      ("iff" . "\x21D4;")
      ("ifr" . "\x1D526;")
      ("igrave" . "\xEC;")
      ("ii" . "\x2148;")
      ("iiiint" . "\x2A0C;")
      ("iiint" . "\x222D;")
      ("iinfin" . "\x29DC;")
      ("iiota" . "\x2129;")
      ("ijlig" . "\x133;")
      ("imacr" . "\x12B;")
      ("image" . "\x2111;")
      ("imagline" . "\x2110;")
      ("imagpart" . "\x2111;")
      ("imath" . "\x131;")
      ("imof" . "\x22B7;")
      ("imped" . "\x1B5;")
      ("in" . "\x2208;")
      ("incare" . "\x2105;")
      ("infin" . "\x221E;")
      ("infintie" . "\x29DD;")
      ("inodot" . "\x131;")
      ("int" . "\x222B;")
      ("intcal" . "\x22BA;")
      ("integers" . "\x2124;")
      ("intercal" . "\x22BA;")
      ("intlarhk" . "\x2A17;")
      ("intprod" . "\x2A3C;")
      ("iocy" . "\x451;")
      ("iogon" . "\x12F;")
      ("iopf" . "\x1D55A;")
      ("iota" . "\x3B9;")
      ("iprod" . "\x2A3C;")
      ("iquest" . "\xBF;")
      ("iscr" . "\x1D4BE;")
      ("isin" . "\x2208;")
      ("isinE" . "\x22F9;")
      ("isindot" . "\x22F5;")
      ("isins" . "\x22F4;")
      ("isinsv" . "\x22F3;")
      ("isinv" . "\x2208;")
      ("it" . "\x2062;")
      ("itilde" . "\x129;")
      ("iukcy" . "\x456;")
      ("iuml" . "\xEF;")
      ("jcirc" . "\x135;")
      ("jcy" . "\x439;")
      ("jfr" . "\x1D527;")
      ("jmath" . "\x237;")
      ("jopf" . "\x1D55B;")
      ("jscr" . "\x1D4BF;")
      ("jsercy" . "\x458;")
      ("jukcy" . "\x454;")
      ("kappa" . "\x3BA;")
      ("kappav" . "\x3F0;")
      ("kcedil" . "\x137;")
      ("kcy" . "\x43A;")
      ("kfr" . "\x1D528;")
      ("kgreen" . "\x138;")
      ("khcy" . "\x445;")
      ("kjcy" . "\x45C;")
      ("kopf" . "\x1D55C;")
      ("kscr" . "\x1D4C0;")
      ("lAarr" . "\x21DA;")
      ("lArr" . "\x21D0;")
      ("lAtail" . "\x291B;")
      ("lBarr" . "\x290E;")
      ("lE" . "\x2266;")
      ("lEg" . "\x2A8B;")
      ("lHar" . "\x2962;")
      ("lacute" . "\x13A;")
      ("laemptyv" . "\x29B4;")
      ("lagran" . "\x2112;")
      ("lambda" . "\x3BB;")
      ("lang" . "\x27E8;")
      ("langd" . "\x2991;")
      ("langle" . "\x27E8;")
      ("lap" . "\x2A85;")
      ("laquo" . "\xAB;")
      ("larr" . "\x2190;")
      ("larrb" . "\x21E4;")
      ("larrbfs" . "\x291F;")
      ("larrfs" . "\x291D;")
      ("larrhk" . "\x21A9;")
      ("larrlp" . "\x21AB;")
      ("larrpl" . "\x2939;")
      ("larrsim" . "\x2973;")
      ("larrtl" . "\x21A2;")
      ("lat" . "\x2AAB;")
      ("latail" . "\x2919;")
      ("late" . "\x2AAD;")
      ("lates" . "\x2AAD;\xFE00;")
      ("lbarr" . "\x290C;")
      ("lbbrk" . "\x2772;")
      ("lbrace" . "{")
      ("lbrack" . "[")
      ("lbrke" . "\x298B;")
      ("lbrksld" . "\x298F;")
      ("lbrkslu" . "\x298D;")
      ("lcaron" . "\x13E;")
      ("lcedil" . "\x13C;")
      ("lceil" . "\x2308;")
      ("lcub" . "{")
      ("lcy" . "\x43B;")
      ("ldca" . "\x2936;")
      ("ldquo" . "\x201C;")
      ("ldquor" . "\x201E;")
      ("ldrdhar" . "\x2967;")
      ("ldrushar" . "\x294B;")
      ("ldsh" . "\x21B2;")
      ("le" . "\x2264;")
      ("leftarrow" . "\x2190;")
      ("leftarrowtail" . "\x21A2;")
      ("leftharpoondown" . "\x21BD;")
      ("leftharpoonup" . "\x21BC;")
      ("leftleftarrows" . "\x21C7;")
      ("leftrightarrow" . "\x2194;")
      ("leftrightarrows" . "\x21C6;")
      ("leftrightharpoons" . "\x21CB;")
      ("leftrightsquigarrow" . "\x21AD;")
      ("leftthreetimes" . "\x22CB;")
      ("leg" . "\x22DA;")
      ("leq" . "\x2264;")
      ("leqq" . "\x2266;")
      ("leqslant" . "\x2A7D;")
      ("les" . "\x2A7D;")
      ("lescc" . "\x2AA8;")
      ("lesdot" . "\x2A7F;")
      ("lesdoto" . "\x2A81;")
      ("lesdotor" . "\x2A83;")
      ("lesg" . "\x22DA;\xFE00;")
      ("lesges" . "\x2A93;")
      ("lessapprox" . "\x2A85;")
      ("lessdot" . "\x22D6;")
      ("lesseqgtr" . "\x22DA;")
      ("lesseqqgtr" . "\x2A8B;")
      ("lessgtr" . "\x2276;")
      ("lesssim" . "\x2272;")
      ("lfisht" . "\x297C;")
      ("lfloor" . "\x230A;")
      ("lfr" . "\x1D529;")
      ("lg" . "\x2276;")
      ("lgE" . "\x2A91;")
      ("lhard" . "\x21BD;")
      ("lharu" . "\x21BC;")
      ("lharul" . "\x296A;")
      ("lhblk" . "\x2584;")
      ("ljcy" . "\x459;")
      ("ll" . "\x226A;")
      ("llarr" . "\x21C7;")
      ("llcorner" . "\x231E;")
      ("llhard" . "\x296B;")
      ("lltri" . "\x25FA;")
      ("lmidot" . "\x140;")
      ("lmoust" . "\x23B0;")
      ("lmoustache" . "\x23B0;")
      ("lnE" . "\x2268;")
      ("lnap" . "\x2A89;")
      ("lnapprox" . "\x2A89;")
      ("lne" . "\x2A87;")
      ("lneq" . "\x2A87;")
      ("lneqq" . "\x2268;")
      ("lnsim" . "\x22E6;")
      ("loang" . "\x27EC;")
      ("loarr" . "\x21FD;")
      ("lobrk" . "\x27E6;")
      ("longleftarrow" . "\x27F5;")
      ("longleftrightarrow" . "\x27F7;")
      ("longmapsto" . "\x27FC;")
      ("longrightarrow" . "\x27F6;")
      ("looparrowleft" . "\x21AB;")
      ("looparrowright" . "\x21AC;")
      ("lopar" . "\x2985;")
      ("lopf" . "\x1D55D;")
      ("loplus" . "\x2A2D;")
      ("lotimes" . "\x2A34;")
      ("lowast" . "\x2217;")
      ("lowbar" . "_")
      ("loz" . "\x25CA;")
      ("lozenge" . "\x25CA;")
      ("lozf" . "\x29EB;")
      ("lpar" . "(")
      ("lparlt" . "\x2993;")
      ("lrarr" . "\x21C6;")
      ("lrcorner" . "\x231F;")
      ("lrhar" . "\x21CB;")
      ("lrhard" . "\x296D;")
      ("lrm" . "\x200E;")
      ("lrtri" . "\x22BF;")
      ("lsaquo" . "\x2039;")
      ("lscr" . "\x1D4C1;")
      ("lsh" . "\x21B0;")
      ("lsim" . "\x2272;")
      ("lsime" . "\x2A8D;")
      ("lsimg" . "\x2A8F;")
      ("lsqb" . "[")
      ("lsquo" . "\x2018;")
      ("lsquor" . "\x201A;")
      ("lstrok" . "\x142;")
      ("lt" . "<")
      ("ltcc" . "\x2AA6;")
      ("ltcir" . "\x2A79;")
      ("ltdot" . "\x22D6;")
      ("lthree" . "\x22CB;")
      ("ltimes" . "\x22C9;")
      ("ltlarr" . "\x2976;")
      ("ltquest" . "\x2A7B;")
      ("ltrPar" . "\x2996;")
      ("ltri" . "\x25C3;")
      ("ltrie" . "\x22B4;")
      ("ltrif" . "\x25C2;")
      ("lurdshar" . "\x294A;")
      ("luruhar" . "\x2966;")
      ("lvertneqq" . "\x2268;\xFE00;")
      ("lvnE" . "\x2268;\xFE00;")
      ("mDDot" . "\x223A;")
      ("macr" . "\xAF;")
      ("male" . "\x2642;")
      ("malt" . "\x2720;")
      ("maltese" . "\x2720;")
      ("map" . "\x21A6;")
      ("mapsto" . "\x21A6;")
      ("mapstodown" . "\x21A7;")
      ("mapstoleft" . "\x21A4;")
      ("mapstoup" . "\x21A5;")
      ("marker" . "\x25AE;")
      ("mcomma" . "\x2A29;")
      ("mcy" . "\x43C;")
      ("mdash" . "\x2014;")
      ("measuredangle" . "\x2221;")
      ("mfr" . "\x1D52A;")
      ("mho" . "\x2127;")
      ("micro" . "\xB5;")
      ("mid" . "\x2223;")
      ("midast" . "*")
      ("midcir" . "\x2AF0;")
      ("middot" . "\xB7;")
      ("minus" . "\x2212;")
      ("minusb" . "\x229F;")
      ("minusd" . "\x2238;")
      ("minusdu" . "\x2A2A;")
      ("mlcp" . "\x2ADB;")
      ("mldr" . "\x2026;")
      ("mnplus" . "\x2213;")
      ("models" . "\x22A7;")
      ("mopf" . "\x1D55E;")
      ("mp" . "\x2213;")
      ("mscr" . "\x1D4C2;")
      ("mstpos" . "\x223E;")
      ("mu" . "\x3BC;")
      ("multimap" . "\x22B8;")
      ("mumap" . "\x22B8;")
      ("nGg" . "\x22D9;\x338;")
      ("nGt" . "\x226B;\x20D2;")
      ("nGtv" . "\x226B;\x338;")
      ("nLeftarrow" . "\x21CD;")
      ("nLeftrightarrow" . "\x21CE;")
      ("nLl" . "\x22D8;\x338;")
      ("nLt" . "\x226A;\x20D2;")
      ("nLtv" . "\x226A;\x338;")
      ("nRightarrow" . "\x21CF;")
      ("nVDash" . "\x22AF;")
      ("nVdash" . "\x22AE;")
      ("nabla" . "\x2207;")
      ("nacute" . "\x144;")
      ("nang" . "\x2220;\x20D2;")
      ("nap" . "\x2249;")
      ("napE" . "\x2A70;\x338;")
      ("napid" . "\x224B;\x338;")
      ("napos" . "\x149;")
      ("napprox" . "\x2249;")
      ("natur" . "\x266E;")
      ("natural" . "\x266E;")
      ("naturals" . "\x2115;")
      ("nbsp" . "\xA0;")
      ("nbump" . "\x224E;\x338;")
      ("nbumpe" . "\x224F;\x338;")
      ("ncap" . "\x2A43;")
      ("ncaron" . "\x148;")
      ("ncedil" . "\x146;")
      ("ncong" . "\x2247;")
      ("ncongdot" . "\x2A6D;\x338;")
      ("ncup" . "\x2A42;")
      ("ncy" . "\x43D;")
      ("ndash" . "\x2013;")
      ("ne" . "\x2260;")
      ("neArr" . "\x21D7;")
      ("nearhk" . "\x2924;")
      ("nearr" . "\x2197;")
      ("nearrow" . "\x2197;")
      ("nedot" . "\x2250;\x338;")
      ("nequiv" . "\x2262;")
      ("nesear" . "\x2928;")
      ("nesim" . "\x2242;\x338;")
      ("nexist" . "\x2204;")
      ("nexists" . "\x2204;")
      ("nfr" . "\x1D52B;")
      ("ngE" . "\x2267;\x338;")
      ("nge" . "\x2271;")
      ("ngeq" . "\x2271;")
      ("ngeqq" . "\x2267;\x338;")
      ("ngeqslant" . "\x2A7E;\x338;")
      ("nges" . "\x2A7E;\x338;")
      ("ngsim" . "\x2275;")
      ("ngt" . "\x226F;")
      ("ngtr" . "\x226F;")
      ("nhArr" . "\x21CE;")
      ("nharr" . "\x21AE;")
      ("nhpar" . "\x2AF2;")
      ("ni" . "\x220B;")
      ("nis" . "\x22FC;")
      ("nisd" . "\x22FA;")
      ("niv" . "\x220B;")
      ("njcy" . "\x45A;")
      ("nlArr" . "\x21CD;")
      ("nlE" . "\x2266;\x338;")
      ("nlarr" . "\x219A;")
      ("nldr" . "\x2025;")
      ("nle" . "\x2270;")
      ("nleftarrow" . "\x219A;")
      ("nleftrightarrow" . "\x21AE;")
      ("nleq" . "\x2270;")
      ("nleqq" . "\x2266;\x338;")
      ("nleqslant" . "\x2A7D;\x338;")
      ("nles" . "\x2A7D;\x338;")
      ("nless" . "\x226E;")
      ("nlsim" . "\x2274;")
      ("nlt" . "\x226E;")
      ("nltri" . "\x22EA;")
      ("nltrie" . "\x22EC;")
      ("nmid" . "\x2224;")
      ("nopf" . "\x1D55F;")
      ("not" . "\xAC;")
      ("notin" . "\x2209;")
      ("notinE" . "\x22F9;\x338;")
      ("notindot" . "\x22F5;\x338;")
      ("notinva" . "\x2209;")
      ("notinvb" . "\x22F7;")
      ("notinvc" . "\x22F6;")
      ("notni" . "\x220C;")
      ("notniva" . "\x220C;")
      ("notnivb" . "\x22FE;")
      ("notnivc" . "\x22FD;")
      ("npar" . "\x2226;")
      ("nparallel" . "\x2226;")
      ("nparsl" . "\x2AFD;\x20E5;")
      ("npart" . "\x2202;\x338;")
      ("npolint" . "\x2A14;")
      ("npr" . "\x2280;")
      ("nprcue" . "\x22E0;")
      ("npre" . "\x2AAF;\x338;")
      ("nprec" . "\x2280;")
      ("npreceq" . "\x2AAF;\x338;")
      ("nrArr" . "\x21CF;")
      ("nrarr" . "\x219B;")
      ("nrarrc" . "\x2933;\x338;")
      ("nrarrw" . "\x219D;\x338;")
      ("nrightarrow" . "\x219B;")
      ("nrtri" . "\x22EB;")
      ("nrtrie" . "\x22ED;")
      ("nsc" . "\x2281;")
      ("nsccue" . "\x22E1;")
      ("nsce" . "\x2AB0;\x338;")
      ("nscr" . "\x1D4C3;")
      ("nshortmid" . "\x2224;")
      ("nshortparallel" . "\x2226;")
      ("nsim" . "\x2241;")
      ("nsime" . "\x2244;")
      ("nsimeq" . "\x2244;")
      ("nsmid" . "\x2224;")
      ("nspar" . "\x2226;")
      ("nsqsube" . "\x22E2;")
      ("nsqsupe" . "\x22E3;")
      ("nsub" . "\x2284;")
      ("nsubE" . "\x2AC5;\x338;")
      ("nsube" . "\x2288;")
      ("nsubset" . "\x2282;\x20D2;")
      ("nsubseteq" . "\x2288;")
      ("nsubseteqq" . "\x2AC5;\x338;")
      ("nsucc" . "\x2281;")
      ("nsucceq" . "\x2AB0;\x338;")
      ("nsup" . "\x2285;")
      ("nsupE" . "\x2AC6;\x338;")
      ("nsupe" . "\x2289;")
      ("nsupset" . "\x2283;\x20D2;")
      ("nsupseteq" . "\x2289;")
      ("nsupseteqq" . "\x2AC6;\x338;")
      ("ntgl" . "\x2279;")
      ("ntilde" . "\xF1;")
      ("ntlg" . "\x2278;")
      ("ntriangleleft" . "\x22EA;")
      ("ntrianglelefteq" . "\x22EC;")
      ("ntriangleright" . "\x22EB;")
      ("ntrianglerighteq" . "\x22ED;")
      ("nu" . "\x3BD;")
      ("num" . "#")
      ("numero" . "\x2116;")
      ("numsp" . "\x2007;")
      ("nvDash" . "\x22AD;")
      ("nvHarr" . "\x2904;")
      ("nvap" . "\x224D;\x20D2;")
      ("nvdash" . "\x22AC;")
      ("nvge" . "\x2265;\x20D2;")
      ("nvgt" . ">\x20D2;")
      ("nvinfin" . "\x29DE;")
      ("nvlArr" . "\x2902;")
      ("nvle" . "\x2264;\x20D2;")
      ("nvlt" . "<\x20D2;")
      ("nvltrie" . "\x22B4;\x20D2;")
      ("nvrArr" . "\x2903;")
      ("nvrtrie" . "\x22B5;\x20D2;")
      ("nvsim" . "\x223C;\x20D2;")
      ("nwArr" . "\x21D6;")
      ("nwarhk" . "\x2923;")
      ("nwarr" . "\x2196;")
      ("nwarrow" . "\x2196;")
      ("nwnear" . "\x2927;")
      ("oS" . "\x24C8;")
      ("oacute" . "\xF3;")
      ("oast" . "\x229B;")
      ("ocir" . "\x229A;")
      ("ocirc" . "\xF4;")
      ("ocy" . "\x43E;")
      ("odash" . "\x229D;")
      ("odblac" . "\x151;")
      ("odiv" . "\x2A38;")
      ("odot" . "\x2299;")
      ("odsold" . "\x29BC;")
      ("oelig" . "\x153;")
      ("ofcir" . "\x29BF;")
      ("ofr" . "\x1D52C;")
      ("ogon" . "\x2DB;")
      ("ograve" . "\xF2;")
      ("ogt" . "\x29C1;")
      ("ohbar" . "\x29B5;")
      ("ohm" . "\x3A9;")
      ("oint" . "\x222E;")
      ("olarr" . "\x21BA;")
      ("olcir" . "\x29BE;")
      ("olcross" . "\x29BB;")
      ("oline" . "\x203E;")
      ("olt" . "\x29C0;")
      ("omacr" . "\x14D;")
      ("omega" . "\x3C9;")
      ("omicron" . "\x3BF;")
      ("omid" . "\x29B6;")
      ("ominus" . "\x2296;")
      ("oopf" . "\x1D560;")
      ("opar" . "\x29B7;")
      ("operp" . "\x29B9;")
      ("oplus" . "\x2295;")
      ("or" . "\x2228;")
      ("orarr" . "\x21BB;")
      ("ord" . "\x2A5D;")
      ("order" . "\x2134;")
      ("orderof" . "\x2134;")
      ("ordf" . "\xAA;")
      ("ordm" . "\xBA;")
      ("origof" . "\x22B6;")
      ("oror" . "\x2A56;")
      ("orslope" . "\x2A57;")
      ("orv" . "\x2A5B;")
      ("oscr" . "\x2134;")
      ("oslash" . "\xF8;")
      ("osol" . "\x2298;")
      ("otilde" . "\xF5;")
      ("otimes" . "\x2297;")
      ("otimesas" . "\x2A36;")
      ("ouml" . "\xF6;")
      ("ovbar" . "\x233D;")
      ("par" . "\x2225;")
      ("para" . "\xB6;")
      ("parallel" . "\x2225;")
      ("parsim" . "\x2AF3;")
      ("parsl" . "\x2AFD;")
      ("part" . "\x2202;")
      ("pcy" . "\x43F;")
      ("percnt" . "%")
      ("period" . ".")
      ("permil" . "\x2030;")
      ("perp" . "\x22A5;")
      ("pertenk" . "\x2031;")
      ("pfr" . "\x1D52D;")
      ("phi" . "\x3C6;")
      ("phiv" . "\x3D5;")
      ("phmmat" . "\x2133;")
      ("phone" . "\x260E;")
      ("pi" . "\x3C0;")
      ("pitchfork" . "\x22D4;")
      ("piv" . "\x3D6;")
      ("planck" . "\x210F;")
      ("planckh" . "\x210E;")
      ("plankv" . "\x210F;")
      ("plus" . "+")
      ("plusacir" . "\x2A23;")
      ("plusb" . "\x229E;")
      ("pluscir" . "\x2A22;")
      ("plusdo" . "\x2214;")
      ("plusdu" . "\x2A25;")
      ("pluse" . "\x2A72;")
      ("plusmn" . "\xB1;")
      ("plussim" . "\x2A26;")
      ("plustwo" . "\x2A27;")
      ("pm" . "\xB1;")
      ("pointint" . "\x2A15;")
      ("popf" . "\x1D561;")
      ("pound" . "\xA3;")
      ("pr" . "\x227A;")
      ("prE" . "\x2AB3;")
      ("prap" . "\x2AB7;")
      ("prcue" . "\x227C;")
      ("pre" . "\x2AAF;")
      ("prec" . "\x227A;")
      ("precapprox" . "\x2AB7;")
      ("preccurlyeq" . "\x227C;")
      ("preceq" . "\x2AAF;")
      ("precnapprox" . "\x2AB9;")
      ("precneqq" . "\x2AB5;")
      ("precnsim" . "\x22E8;")
      ("precsim" . "\x227E;")
      ("prime" . "\x2032;")
      ("primes" . "\x2119;")
      ("prnE" . "\x2AB5;")
      ("prnap" . "\x2AB9;")
      ("prnsim" . "\x22E8;")
      ("prod" . "\x220F;")
      ("profalar" . "\x232E;")
      ("profline" . "\x2312;")
      ("profsurf" . "\x2313;")
      ("prop" . "\x221D;")
      ("propto" . "\x221D;")
      ("prsim" . "\x227E;")
      ("prurel" . "\x22B0;")
      ("pscr" . "\x1D4C5;")
      ("psi" . "\x3C8;")
      ("puncsp" . "\x2008;")
      ("qfr" . "\x1D52E;")
      ("qint" . "\x2A0C;")
      ("qopf" . "\x1D562;")
      ("qprime" . "\x2057;")
      ("qscr" . "\x1D4C6;")
      ("quaternions" . "\x210D;")
      ("quatint" . "\x2A16;")
      ("quest" . "?")
      ("questeq" . "\x225F;")
      ("quot" . "\"")
      ("rAarr" . "\x21DB;")
      ("rArr" . "\x21D2;")
      ("rAtail" . "\x291C;")
      ("rBarr" . "\x290F;")
      ("rHar" . "\x2964;")
      ("race" . "\x223D;\x331;")
      ("racute" . "\x155;")
      ("radic" . "\x221A;")
      ("raemptyv" . "\x29B3;")
      ("rang" . "\x27E9;")
      ("rangd" . "\x2992;")
      ("range" . "\x29A5;")
      ("rangle" . "\x27E9;")
      ("raquo" . "\xBB;")
      ("rarr" . "\x2192;")
      ("rarrap" . "\x2975;")
      ("rarrb" . "\x21E5;")
      ("rarrbfs" . "\x2920;")
      ("rarrc" . "\x2933;")
      ("rarrfs" . "\x291E;")
      ("rarrhk" . "\x21AA;")
      ("rarrlp" . "\x21AC;")
      ("rarrpl" . "\x2945;")
      ("rarrsim" . "\x2974;")
      ("rarrtl" . "\x21A3;")
      ("rarrw" . "\x219D;")
      ("ratail" . "\x291A;")
      ("ratio" . "\x2236;")
      ("rationals" . "\x211A;")
      ("rbarr" . "\x290D;")
      ("rbbrk" . "\x2773;")
      ("rbrace" . "}")
      ("rbrack" . "]")
      ("rbrke" . "\x298C;")
      ("rbrksld" . "\x298E;")
      ("rbrkslu" . "\x2990;")
      ("rcaron" . "\x159;")
      ("rcedil" . "\x157;")
      ("rceil" . "\x2309;")
      ("rcub" . "}")
      ("rcy" . "\x440;")
      ("rdca" . "\x2937;")
      ("rdldhar" . "\x2969;")
      ("rdquo" . "\x201D;")
      ("rdquor" . "\x201D;")
      ("rdsh" . "\x21B3;")
      ("real" . "\x211C;")
      ("realine" . "\x211B;")
      ("realpart" . "\x211C;")
      ("reals" . "\x211D;")
      ("rect" . "\x25AD;")
      ("reg" . "\xAE;")
      ("rfisht" . "\x297D;")
      ("rfloor" . "\x230B;")
      ("rfr" . "\x1D52F;")
      ("rhard" . "\x21C1;")
      ("rharu" . "\x21C0;")
      ("rharul" . "\x296C;")
      ("rho" . "\x3C1;")
      ("rhov" . "\x3F1;")
      ("rightarrow" . "\x2192;")
      ("rightarrowtail" . "\x21A3;")
      ("rightharpoondown" . "\x21C1;")
      ("rightharpoonup" . "\x21C0;")
      ("rightleftarrows" . "\x21C4;")
      ("rightleftharpoons" . "\x21CC;")
      ("rightrightarrows" . "\x21C9;")
      ("rightsquigarrow" . "\x219D;")
      ("rightthreetimes" . "\x22CC;")
      ("ring" . "\x2DA;")
      ("risingdotseq" . "\x2253;")
      ("rlarr" . "\x21C4;")
      ("rlhar" . "\x21CC;")
      ("rlm" . "\x200F;")
      ("rmoust" . "\x23B1;")
      ("rmoustache" . "\x23B1;")
      ("rnmid" . "\x2AEE;")
      ("roang" . "\x27ED;")
      ("roarr" . "\x21FE;")
      ("robrk" . "\x27E7;")
      ("ropar" . "\x2986;")
      ("ropf" . "\x1D563;")
      ("roplus" . "\x2A2E;")
      ("rotimes" . "\x2A35;")
      ("rpar" . ")")
      ("rpargt" . "\x2994;")
      ("rppolint" . "\x2A12;")
      ("rrarr" . "\x21C9;")
      ("rsaquo" . "\x203A;")
      ("rscr" . "\x1D4C7;")
      ("rsh" . "\x21B1;")
      ("rsqb" . "]")
      ("rsquo" . "\x2019;")
      ("rsquor" . "\x2019;")
      ("rthree" . "\x22CC;")
      ("rtimes" . "\x22CA;")
      ("rtri" . "\x25B9;")
      ("rtrie" . "\x22B5;")
      ("rtrif" . "\x25B8;")
      ("rtriltri" . "\x29CE;")
      ("ruluhar" . "\x2968;")
      ("rx" . "\x211E;")
      ("sacute" . "\x15B;")
      ("sbquo" . "\x201A;")
      ("sc" . "\x227B;")
      ("scE" . "\x2AB4;")
      ("scap" . "\x2AB8;")
      ("scaron" . "\x161;")
      ("sccue" . "\x227D;")
      ("sce" . "\x2AB0;")
      ("scedil" . "\x15F;")
      ("scirc" . "\x15D;")
      ("scnE" . "\x2AB6;")
      ("scnap" . "\x2ABA;")
      ("scnsim" . "\x22E9;")
      ("scpolint" . "\x2A13;")
      ("scsim" . "\x227F;")
      ("scy" . "\x441;")
      ("sdot" . "\x22C5;")
      ("sdotb" . "\x22A1;")
      ("sdote" . "\x2A66;")
      ("seArr" . "\x21D8;")
      ("searhk" . "\x2925;")
      ("searr" . "\x2198;")
      ("searrow" . "\x2198;")
      ("sect" . "\xA7;")
      ("semi" . ";")
      ("seswar" . "\x2929;")
      ("setminus" . "\x2216;")
      ("setmn" . "\x2216;")
      ("sext" . "\x2736;")
      ("sfr" . "\x1D530;")
      ("sfrown" . "\x2322;")
      ("sharp" . "\x266F;")
      ("shchcy" . "\x449;")
      ("shcy" . "\x448;")
      ("shortmid" . "\x2223;")
      ("shortparallel" . "\x2225;")
      ("shy" . "\xAD;")
      ("sigma" . "\x3C3;")
      ("sigmaf" . "\x3C2;")
      ("sigmav" . "\x3C2;")
      ("sim" . "\x223C;")
      ("simdot" . "\x2A6A;")
      ("sime" . "\x2243;")
      ("simeq" . "\x2243;")
      ("simg" . "\x2A9E;")
      ("simgE" . "\x2AA0;")
      ("siml" . "\x2A9D;")
      ("simlE" . "\x2A9F;")
      ("simne" . "\x2246;")
      ("simplus" . "\x2A24;")
      ("simrarr" . "\x2972;")
      ("slarr" . "\x2190;")
      ("smallsetminus" . "\x2216;")
      ("smashp" . "\x2A33;")
      ("smeparsl" . "\x29E4;")
      ("smid" . "\x2223;")
      ("smile" . "\x2323;")
      ("smt" . "\x2AAA;")
      ("smte" . "\x2AAC;")
      ("smtes" . "\x2AAC;\xFE00;")
      ("softcy" . "\x44C;")
      ("sol" . "/")
      ("solb" . "\x29C4;")
      ("solbar" . "\x233F;")
      ("sopf" . "\x1D564;")
      ("spades" . "\x2660;")
      ("spadesuit" . "\x2660;")
      ("spar" . "\x2225;")
      ("sqcap" . "\x2293;")
      ("sqcaps" . "\x2293;\xFE00;")
      ("sqcup" . "\x2294;")
      ("sqcups" . "\x2294;\xFE00;")
      ("sqsub" . "\x228F;")
      ("sqsube" . "\x2291;")
      ("sqsubset" . "\x228F;")
      ("sqsubseteq" . "\x2291;")
      ("sqsup" . "\x2290;")
      ("sqsupe" . "\x2292;")
      ("sqsupset" . "\x2290;")
      ("sqsupseteq" . "\x2292;")
      ("squ" . "\x25A1;")
      ("square" . "\x25A1;")
      ("squarf" . "\x25AA;")
      ("squf" . "\x25AA;")
      ("srarr" . "\x2192;")
      ("sscr" . "\x1D4C8;")
      ("ssetmn" . "\x2216;")
      ("ssmile" . "\x2323;")
      ("sstarf" . "\x22C6;")
      ("star" . "\x2606;")
      ("starf" . "\x2605;")
      ("straightepsilon" . "\x3F5;")
      ("straightphi" . "\x3D5;")
      ("strns" . "\xAF;")
      ("sub" . "\x2282;")
      ("subE" . "\x2AC5;")
      ("subdot" . "\x2ABD;")
      ("sube" . "\x2286;")
      ("subedot" . "\x2AC3;")
      ("submult" . "\x2AC1;")
      ("subnE" . "\x2ACB;")
      ("subne" . "\x228A;")
      ("subplus" . "\x2ABF;")
      ("subrarr" . "\x2979;")
      ("subset" . "\x2282;")
      ("subseteq" . "\x2286;")
      ("subseteqq" . "\x2AC5;")
      ("subsetneq" . "\x228A;")
      ("subsetneqq" . "\x2ACB;")
      ("subsim" . "\x2AC7;")
      ("subsub" . "\x2AD5;")
      ("subsup" . "\x2AD3;")
      ("succ" . "\x227B;")
      ("succapprox" . "\x2AB8;")
      ("succcurlyeq" . "\x227D;")
      ("succeq" . "\x2AB0;")
      ("succnapprox" . "\x2ABA;")
      ("succneqq" . "\x2AB6;")
      ("succnsim" . "\x22E9;")
      ("succsim" . "\x227F;")
      ("sum" . "\x2211;")
      ("sung" . "\x266A;")
      ("sup" . "\x2283;")
      ("sup1" . "\xB9;")
      ("sup2" . "\xB2;")
      ("sup3" . "\xB3;")
      ("supE" . "\x2AC6;")
      ("supdot" . "\x2ABE;")
      ("supdsub" . "\x2AD8;")
      ("supe" . "\x2287;")
      ("supedot" . "\x2AC4;")
      ("suphsol" . "\x27C9;")
      ("suphsub" . "\x2AD7;")
      ("suplarr" . "\x297B;")
      ("supmult" . "\x2AC2;")
      ("supnE" . "\x2ACC;")
      ("supne" . "\x228B;")
      ("supplus" . "\x2AC0;")
      ("supset" . "\x2283;")
      ("supseteq" . "\x2287;")
      ("supseteqq" . "\x2AC6;")
      ("supsetneq" . "\x228B;")
      ("supsetneqq" . "\x2ACC;")
      ("supsim" . "\x2AC8;")
      ("supsub" . "\x2AD4;")
      ("supsup" . "\x2AD6;")
      ("swArr" . "\x21D9;")
      ("swarhk" . "\x2926;")
      ("swarr" . "\x2199;")
      ("swarrow" . "\x2199;")
      ("swnwar" . "\x292A;")
      ("szlig" . "\xDF;")
      ("target" . "\x2316;")
      ("tau" . "\x3C4;")
      ("tbrk" . "\x23B4;")
      ("tcaron" . "\x165;")
      ("tcedil" . "\x163;")
      ("tcy" . "\x442;")
      ("tdot" . "\x20DB;")
      ("telrec" . "\x2315;")
      ("tfr" . "\x1D531;")
      ("there4" . "\x2234;")
      ("therefore" . "\x2234;")
      ("theta" . "\x3B8;")
      ("thetasym" . "\x3D1;")
      ("thetav" . "\x3D1;")
      ("thickapprox" . "\x2248;")
      ("thicksim" . "\x223C;")
      ("thinsp" . "\x2009;")
      ("thkap" . "\x2248;")
      ("thksim" . "\x223C;")
      ("thorn" . "\xFE;")
      ("tilde" . "\x2DC;")
      ("times" . "\xD7;")
      ("timesb" . "\x22A0;")
      ("timesbar" . "\x2A31;")
      ("timesd" . "\x2A30;")
      ("tint" . "\x222D;")
      ("toea" . "\x2928;")
      ("top" . "\x22A4;")
      ("topbot" . "\x2336;")
      ("topcir" . "\x2AF1;")
      ("topf" . "\x1D565;")
      ("topfork" . "\x2ADA;")
      ("tosa" . "\x2929;")
      ("tprime" . "\x2034;")
      ("trade" . "\x2122;")
      ("triangle" . "\x25B5;")
      ("triangledown" . "\x25BF;")
      ("triangleleft" . "\x25C3;")
      ("trianglelefteq" . "\x22B4;")
      ("triangleq" . "\x225C;")
      ("triangleright" . "\x25B9;")
      ("trianglerighteq" . "\x22B5;")
      ("tridot" . "\x25EC;")
      ("trie" . "\x225C;")
      ("triminus" . "\x2A3A;")
      ("triplus" . "\x2A39;")
      ("trisb" . "\x29CD;")
      ("tritime" . "\x2A3B;")
      ("trpezium" . "\x23E2;")
      ("tscr" . "\x1D4C9;")
      ("tscy" . "\x446;")
      ("tshcy" . "\x45B;")
      ("tstrok" . "\x167;")
      ("twixt" . "\x226C;")
      ("twoheadleftarrow" . "\x219E;")
      ("twoheadrightarrow" . "\x21A0;")
      ("uArr" . "\x21D1;")
      ("uHar" . "\x2963;")
      ("uacute" . "\xFA;")
      ("uarr" . "\x2191;")
      ("ubrcy" . "\x45E;")
      ("ubreve" . "\x16D;")
      ("ucirc" . "\xFB;")
      ("ucy" . "\x443;")
      ("udarr" . "\x21C5;")
      ("udblac" . "\x171;")
      ("udhar" . "\x296E;")
      ("ufisht" . "\x297E;")
      ("ufr" . "\x1D532;")
      ("ugrave" . "\xF9;")
      ("uharl" . "\x21BF;")
      ("uharr" . "\x21BE;")
      ("uhblk" . "\x2580;")
      ("ulcorn" . "\x231C;")
      ("ulcorner" . "\x231C;")
      ("ulcrop" . "\x230F;")
      ("ultri" . "\x25F8;")
      ("umacr" . "\x16B;")
      ("uml" . "\xA8;")
      ("uogon" . "\x173;")
      ("uopf" . "\x1D566;")
      ("uparrow" . "\x2191;")
      ("updownarrow" . "\x2195;")
      ("upharpoonleft" . "\x21BF;")
      ("upharpoonright" . "\x21BE;")
      ("uplus" . "\x228E;")
      ("upsi" . "\x3C5;")
      ("upsih" . "\x3D2;")
      ("upsilon" . "\x3C5;")
      ("upuparrows" . "\x21C8;")
      ("urcorn" . "\x231D;")
      ("urcorner" . "\x231D;")
      ("urcrop" . "\x230E;")
      ("uring" . "\x16F;")
      ("urtri" . "\x25F9;")
      ("uscr" . "\x1D4CA;")
      ("utdot" . "\x22F0;")
      ("utilde" . "\x169;")
      ("utri" . "\x25B5;")
      ("utrif" . "\x25B4;")
      ("uuarr" . "\x21C8;")
      ("uuml" . "\xFC;")
      ("uwangle" . "\x29A7;")
      ("vArr" . "\x21D5;")
      ("vBar" . "\x2AE8;")
      ("vBarv" . "\x2AE9;")
      ("vDash" . "\x22A8;")
      ("vangrt" . "\x299C;")
      ("varepsilon" . "\x3F5;")
      ("varkappa" . "\x3F0;")
      ("varnothing" . "\x2205;")
      ("varphi" . "\x3D5;")
      ("varpi" . "\x3D6;")
      ("varpropto" . "\x221D;")
      ("varr" . "\x2195;")
      ("varrho" . "\x3F1;")
      ("varsigma" . "\x3C2;")
      ("varsubsetneq" . "\x228A;\xFE00;")
      ("varsubsetneqq" . "\x2ACB;\xFE00;")
      ("varsupsetneq" . "\x228B;\xFE00;")
      ("varsupsetneqq" . "\x2ACC;\xFE00;")
      ("vartheta" . "\x3D1;")
      ("vartriangleleft" . "\x22B2;")
      ("vartriangleright" . "\x22B3;")
      ("vcy" . "\x432;")
      ("vdash" . "\x22A2;")
      ("vee" . "\x2228;")
      ("veebar" . "\x22BB;")
      ("veeeq" . "\x225A;")
      ("vellip" . "\x22EE;")
      ("verbar" . "|")
      ("vert" . "|")
      ("vfr" . "\x1D533;")
      ("vltri" . "\x22B2;")
      ("vnsub" . "\x2282;\x20D2;")
      ("vnsup" . "\x2283;\x20D2;")
      ("vopf" . "\x1D567;")
      ("vprop" . "\x221D;")
      ("vrtri" . "\x22B3;")
      ("vscr" . "\x1D4CB;")
      ("vsubnE" . "\x2ACB;\xFE00;")
      ("vsubne" . "\x228A;\xFE00;")
      ("vsupnE" . "\x2ACC;\xFE00;")
      ("vsupne" . "\x228B;\xFE00;")
      ("vzigzag" . "\x299A;")
      ("wcirc" . "\x175;")
      ("wedbar" . "\x2A5F;")
      ("wedge" . "\x2227;")
      ("wedgeq" . "\x2259;")
      ("weierp" . "\x2118;")
      ("wfr" . "\x1D534;")
      ("wopf" . "\x1D568;")
      ("wp" . "\x2118;")
      ("wr" . "\x2240;")
      ("wreath" . "\x2240;")
      ("wscr" . "\x1D4CC;")
      ("xcap" . "\x22C2;")
      ("xcirc" . "\x25EF;")
      ("xcup" . "\x22C3;")
      ("xdtri" . "\x25BD;")
      ("xfr" . "\x1D535;")
      ("xhArr" . "\x27FA;")
      ("xharr" . "\x27F7;")
      ("xi" . "\x3BE;")
      ("xlArr" . "\x27F8;")
      ("xlarr" . "\x27F5;")
      ("xmap" . "\x27FC;")
      ("xnis" . "\x22FB;")
      ("xodot" . "\x2A00;")
      ("xopf" . "\x1D569;")
      ("xoplus" . "\x2A01;")
      ("xotime" . "\x2A02;")
      ("xrArr" . "\x27F9;")
      ("xrarr" . "\x27F6;")
      ("xscr" . "\x1D4CD;")
      ("xsqcup" . "\x2A06;")
      ("xuplus" . "\x2A04;")
      ("xutri" . "\x25B3;")
      ("xvee" . "\x22C1;")
      ("xwedge" . "\x22C0;")
      ("yacute" . "\xFD;")
      ("yacy" . "\x44F;")
      ("ycirc" . "\x177;")
      ("ycy" . "\x44B;")
      ("yen" . "\xA5;")
      ("yfr" . "\x1D536;")
      ("yicy" . "\x457;")
      ("yopf" . "\x1D56A;")
      ("yscr" . "\x1D4CE;")
      ("yucy" . "\x44E;")
      ("yuml" . "\xFF;")
      ("zacute" . "\x17A;")
      ("zcaron" . "\x17E;")
      ("zcy" . "\x437;")
      ("zdot" . "\x17C;")
      ("zeetrf" . "\x2128;")
      ("zeta" . "\x3B6;")
      ("zfr" . "\x1D537;")
      ("zhcy" . "\x436;")
      ("zigrarr" . "\x21DD;")
      ("zopf" . "\x1D56B;")
      ("zscr" . "\x1D4CF;")
      ("zwj" . "\x200D;")
      ("zwnj" . "\x200C;")
      ))

  ;; semicolon-optional (legacy HTML4) entity names
  (define html-entity-legacy-names
    '#(
      "AElig" "AMP" "Aacute" "Acirc" "Agrave" "Aring"
      "Atilde" "Auml" "COPY" "Ccedil" "ETH" "Eacute"
      "Ecirc" "Egrave" "Euml" "GT" "Iacute" "Icirc"
      "Igrave" "Iuml" "LT" "Ntilde" "Oacute" "Ocirc"
      "Ograve" "Oslash" "Otilde" "Ouml" "QUOT" "REG"
      "THORN" "Uacute" "Ucirc" "Ugrave" "Uuml" "Yacute"
      "aacute" "acirc" "acute" "aelig" "agrave" "amp"
      "aring" "atilde" "auml" "brvbar" "ccedil" "cedil"
      "cent" "copy" "curren" "deg" "divide" "eacute"
      "ecirc" "egrave" "eth" "euml" "frac12" "frac14"
      "frac34" "gt" "iacute" "icirc" "iexcl" "igrave"
      "iquest" "iuml" "laquo" "lt" "macr" "micro"
      "middot" "nbsp" "not" "ntilde" "oacute" "ocirc"
      "ograve" "ordf" "ordm" "oslash" "otilde" "ouml"
      "para" "plusmn" "pound" "quot" "raquo" "reg"
      "sect" "shy" "sup1" "sup2" "sup3" "szlig"
      "thorn" "times" "uacute" "ucirc" "ugrave" "uml"
      "uuml" "yacute" "yen" "yuml"
      ))

  ;; WHATWG 13.2.5.73 numeric reference replacements
  (define html-entity-numeric-replacement-entries
    '#(
      ("0" . "\xFFFD;")
      ("128" . "\x20AC;")
      ("130" . "\x201A;")
      ("131" . "\x192;")
      ("132" . "\x201E;")
      ("133" . "\x2026;")
      ("134" . "\x2020;")
      ("135" . "\x2021;")
      ("136" . "\x2C6;")
      ("137" . "\x2030;")
      ("138" . "\x160;")
      ("139" . "\x2039;")
      ("140" . "\x152;")
      ("142" . "\x17D;")
      ("145" . "\x2018;")
      ("146" . "\x2019;")
      ("147" . "\x201C;")
      ("148" . "\x201D;")
      ("149" . "\x2022;")
      ("150" . "\x2013;")
      ("151" . "\x2014;")
      ("152" . "\x2DC;")
      ("153" . "\x2122;")
      ("154" . "\x161;")
      ("155" . "\x203A;")
      ("156" . "\x153;")
      ("158" . "\x17E;")
      ("159" . "\x178;")
      ))

  ;; SVG tag name case fixups
  (define html-svg-tag-name-adjustment-entries
    '#(
      ("altglyph" . "altGlyph")
      ("altglyphdef" . "altGlyphDef")
      ("altglyphitem" . "altGlyphItem")
      ("animatecolor" . "animateColor")
      ("animatemotion" . "animateMotion")
      ("animatetransform" . "animateTransform")
      ("clippath" . "clipPath")
      ("feblend" . "feBlend")
      ("fecolormatrix" . "feColorMatrix")
      ("fecomponenttransfer" . "feComponentTransfer")
      ("fecomposite" . "feComposite")
      ("feconvolvematrix" . "feConvolveMatrix")
      ("fediffuselighting" . "feDiffuseLighting")
      ("fedisplacementmap" . "feDisplacementMap")
      ("fedistantlight" . "feDistantLight")
      ("feflood" . "feFlood")
      ("fefunca" . "feFuncA")
      ("fefuncb" . "feFuncB")
      ("fefuncg" . "feFuncG")
      ("fefuncr" . "feFuncR")
      ("fegaussianblur" . "feGaussianBlur")
      ("feimage" . "feImage")
      ("femerge" . "feMerge")
      ("femergenode" . "feMergeNode")
      ("femorphology" . "feMorphology")
      ("feoffset" . "feOffset")
      ("fepointlight" . "fePointLight")
      ("fespecularlighting" . "feSpecularLighting")
      ("fespotlight" . "feSpotLight")
      ("fetile" . "feTile")
      ("feturbulence" . "feTurbulence")
      ("foreignobject" . "foreignObject")
      ("glyphref" . "glyphRef")
      ("lineargradient" . "linearGradient")
      ("radialgradient" . "radialGradient")
      ("textpath" . "textPath")
      ))

  ;; SVG attribute name case fixups
  (define html-svg-attribute-adjustment-entries
    '#(
      ("attributename" . "attributeName")
      ("attributetype" . "attributeType")
      ("basefrequency" . "baseFrequency")
      ("baseprofile" . "baseProfile")
      ("calcmode" . "calcMode")
      ("clippathunits" . "clipPathUnits")
      ("diffuseconstant" . "diffuseConstant")
      ("edgemode" . "edgeMode")
      ("filterunits" . "filterUnits")
      ("glyphref" . "glyphRef")
      ("gradienttransform" . "gradientTransform")
      ("gradientunits" . "gradientUnits")
      ("kernelmatrix" . "kernelMatrix")
      ("kernelunitlength" . "kernelUnitLength")
      ("keypoints" . "keyPoints")
      ("keysplines" . "keySplines")
      ("keytimes" . "keyTimes")
      ("lengthadjust" . "lengthAdjust")
      ("limitingconeangle" . "limitingConeAngle")
      ("markerheight" . "markerHeight")
      ("markerunits" . "markerUnits")
      ("markerwidth" . "markerWidth")
      ("maskcontentunits" . "maskContentUnits")
      ("maskunits" . "maskUnits")
      ("numoctaves" . "numOctaves")
      ("pathlength" . "pathLength")
      ("patterncontentunits" . "patternContentUnits")
      ("patterntransform" . "patternTransform")
      ("patternunits" . "patternUnits")
      ("pointsatx" . "pointsAtX")
      ("pointsaty" . "pointsAtY")
      ("pointsatz" . "pointsAtZ")
      ("preservealpha" . "preserveAlpha")
      ("preserveaspectratio" . "preserveAspectRatio")
      ("primitiveunits" . "primitiveUnits")
      ("refx" . "refX")
      ("refy" . "refY")
      ("repeatcount" . "repeatCount")
      ("repeatdur" . "repeatDur")
      ("requiredextensions" . "requiredExtensions")
      ("requiredfeatures" . "requiredFeatures")
      ("specularconstant" . "specularConstant")
      ("specularexponent" . "specularExponent")
      ("spreadmethod" . "spreadMethod")
      ("startoffset" . "startOffset")
      ("stddeviation" . "stdDeviation")
      ("stitchtiles" . "stitchTiles")
      ("surfacescale" . "surfaceScale")
      ("systemlanguage" . "systemLanguage")
      ("tablevalues" . "tableValues")
      ("targetx" . "targetX")
      ("targety" . "targetY")
      ("textlength" . "textLength")
      ("viewbox" . "viewBox")
      ("viewtarget" . "viewTarget")
      ("xchannelselector" . "xChannelSelector")
      ("ychannelselector" . "yChannelSelector")
      ("zoomandpan" . "zoomAndPan")
      ))

  ;; MathML attribute name case fixups
  (define html-mathml-attribute-adjustment-entries
    '#(
      ("definitionurl" . "definitionURL")
      ))

  ;; namespaced attributes in foreign content
  (define html-foreign-attribute-adjustment-entries
    '#(
      ("xlink:actuate" . "xlink:actuate")
      ("xlink:arcrole" . "xlink:arcrole")
      ("xlink:href" . "xlink:href")
      ("xlink:role" . "xlink:role")
      ("xlink:show" . "xlink:show")
      ("xlink:title" . "xlink:title")
      ("xlink:type" . "xlink:type")
      ("xml:lang" . "xml:lang")
      ("xml:space" . "xml:space")
      ("xmlns" . "xmlns")
      ("xmlns:xlink" . "xmlns:xlink")
      ))

  ;; formatting elements
  (define html-formatting-element-names
    '#(
      "a" "b" "big" "code" "em" "font"
      "i" "nobr" "s" "small" "strike" "strong"
      "tt" "u"
      ))

  ;; special elements
  (define html-special-element-names
    '#(
      "address" "applet" "area" "article" "aside" "base"
      "basefont" "bgsound" "blockquote" "body" "br" "button"
      "caption" "center" "col" "colgroup" "dd" "details"
      "dialog" "dir" "div" "dl" "dt" "embed"
      "fieldset" "figcaption" "figure" "footer" "form" "frame"
      "frameset" "h1" "h2" "h3" "h4" "h5"
      "h6" "head" "header" "hgroup" "hr" "html"
      "iframe" "img" "input" "keygen" "li" "link"
      "listing" "main" "marquee" "menu" "meta" "nav"
      "noembed" "noframes" "noscript" "object" "ol" "p"
      "param" "plaintext" "pre" "script" "search" "section"
      "select" "source" "style" "summary" "table" "tbody"
      "td" "template" "textarea" "tfoot" "th" "thead"
      "title" "tr" "track" "ul" "wbr"
      ))

  ;; HTML elements that break out of foreign content
  (define html-foreign-breakout-element-names
    '#(
      "b" "big" "blockquote" "body" "br" "center"
      "code" "dd" "div" "dl" "dt" "em"
      "embed" "h1" "h2" "h3" "h4" "h5"
      "h6" "head" "hr" "i" "img" "li"
      "listing" "menu" "meta" "nobr" "ol" "p"
      "pre" "ruby" "s" "small" "span" "strike"
      "strong" "sub" "sup" "table" "tt" "u"
      "ul" "var"
      ))

  ;; void elements
  (define html-void-element-names
    '#(
      "area" "base" "br" "col" "embed" "hr"
      "img" "input" "link" "meta" "param" "source"
      "track" "wbr"
      ))

  ;; implied end tags
  (define html-implied-end-tag-names
    '#(
      "dd" "dt" "li" "optgroup" "option" "p"
      "rb" "rp" "rt" "rtc"
      ))

  ;; default scope terminators
  (define html-default-scope-terminator-names
    '#(
      "applet" "caption" "html" "marquee" "object" "table"
      "td" "template" "th"
      ))

  ;; table scope terminators
  (define html-table-scope-terminator-names
    '#(
      "html" "table" "template"
      ))

  ;; DOCTYPE public identifier prefixes forcing quirks mode
  (define html-quirky-public-prefixes
    '#(
      "-//advasoft ltd//dtd html 3.0 aswedit + extensions//"
      "-//as//dtd html 3.0 aswedit + extensions//"
      "-//ietf//dtd html 2.0 level 1//"
      "-//ietf//dtd html 2.0 level 2//"
      "-//ietf//dtd html 2.0 strict level 1//"
      "-//ietf//dtd html 2.0 strict level 2//"
      "-//ietf//dtd html 2.0 strict//"
      "-//ietf//dtd html 2.0//"
      "-//ietf//dtd html 2.1e//"
      "-//ietf//dtd html 3.0//"
      "-//ietf//dtd html 3.2 final//"
      "-//ietf//dtd html 3.2//"
      "-//ietf//dtd html 3//"
      "-//ietf//dtd html level 0//"
      "-//ietf//dtd html level 1//"
      "-//ietf//dtd html level 2//"
      "-//ietf//dtd html level 3//"
      "-//ietf//dtd html strict level 0//"
      "-//ietf//dtd html strict level 1//"
      "-//ietf//dtd html strict level 2//"
      "-//ietf//dtd html strict level 3//"
      "-//ietf//dtd html strict//"
      "-//ietf//dtd html//"
      "-//metrius//dtd metrius presentational//"
      "-//microsoft//dtd internet explorer 2.0 html strict//"
      "-//microsoft//dtd internet explorer 2.0 html//"
      "-//microsoft//dtd internet explorer 2.0 tables//"
      "-//microsoft//dtd internet explorer 3.0 html strict//"
      "-//microsoft//dtd internet explorer 3.0 html//"
      "-//microsoft//dtd internet explorer 3.0 tables//"
      "-//netscape comm. corp.//dtd html//"
      "-//netscape comm. corp.//dtd strict html//"
      "-//o'reilly and associates//dtd html 2.0//"
      "-//o'reilly and associates//dtd html extended 1.0//"
      "-//o'reilly and associates//dtd html extended relaxed 1.0//"
      "-//softquad software//dtd hotmetal pro 6.0::19990601::extensions to html 4.0//"
      "-//softquad//dtd hotmetal pro 4.0::19971010::extensions to html 4.0//"
      "-//spyglass//dtd html 2.0 extended//"
      "-//sq//dtd html 2.0 hotmetal + extensions//"
      "-//sun microsystems corp.//dtd hotjava html//"
      "-//sun microsystems corp.//dtd hotjava strict html//"
      "-//w3c//dtd html 3 1995-03-24//"
      "-//w3c//dtd html 3.2 draft//"
      "-//w3c//dtd html 3.2 final//"
      "-//w3c//dtd html 3.2//"
      "-//w3c//dtd html 3.2s draft//"
      "-//w3c//dtd html 4.0 frameset//"
      "-//w3c//dtd html 4.0 transitional//"
      "-//w3c//dtd html experimental 19960712//"
      "-//w3c//dtd html experimental 970421//"
      "-//w3c//dtd html experimental 970421//"
      "-//w3c//dtd w3 html//"
      "-//w3o//dtd w3 html 3.0//"
      "-//webtechs//dtd mozilla html 2.0//"
      "-//webtechs//dtd mozilla html//"
      ))

  ;; DOCTYPE public identifiers forcing quirks mode
  (define html-quirky-public-matches
    '#(
      "-//w3o//dtd w3 html strict 3.0//en//"
      "-/w3c/dtd html 4.0 transitional/en"
      "html"
      ))

  ;; DOCTYPE system identifiers forcing quirks mode
  (define html-quirky-system-matches
    '#(
      "http://www.ibm.com/data/dtd/v11/ibmxhtml1-transitional.dtd"
      ))

  ;; DOCTYPE public identifier prefixes forcing limited-quirks mode
  (define html-limited-quirky-public-prefixes
    '#(
      "-//w3c//dtd xhtml 1.0 frameset//"
      "-//w3c//dtd xhtml 1.0 transitional//"
      ))

  ;; HTML 4.01 public identifier prefixes
  (define html4-public-prefixes
    '#(
      "-//w3c//dtd html 4.01 frameset//"
      "-//w3c//dtd html 4.01 transitional//"
      ))
  

  ;; ====================================================================
  ;; Section 2 -- character references
  ;; ====================================================================
  ;; Layer 1 -- HTML5 character references (WHATWG 13.2.5), ported from
  ;; submodules/justhtml/src/justhtml/core/entities.py.

  (define replacement-character-string (string (integer->char #xFFFD)))

  ;; ASCII helpers shared by every later layer.  HTML markup matching is
  ;; ASCII case-insensitive, never Unicode case-insensitive.

  (define (char-ascii-alphabetic? c)
    (or (and (char<=? #\a c) (char<=? c #\z))
        (and (char<=? #\A c) (char<=? c #\Z))))

  (define (char-ascii-digit? c)
    (and (char<=? #\0 c) (char<=? c #\9)))

  (define (char-ascii-alphanumeric? c)
    (or (char-ascii-alphabetic? c) (char-ascii-digit? c)))

  (define (char-ascii-hexadecimal-digit? c)
    (or (char-ascii-digit? c)
        (and (char<=? #\a c) (char<=? c #\f))
        (and (char<=? #\A c) (char<=? c #\F))))

  (define (char-ascii-lowercase c)
    (if (and (char<=? #\A c) (char<=? c #\Z))
      (integer->char (fx+ (char->integer c) 32))
      c))

  (define (string-ascii-lowercase text)
    (let* ((size (string-length text))
           (result (make-string size)))
      (let loop ((i 0))
        (if (fx= i size)
          result
          (begin
            (string-set! result i (char-ascii-lowercase (string-ref text i)))
            (loop (fx+ i 1)))))))

  (define (string-ascii-equal? a b)
    (and (fx= (string-length a) (string-length b))
         (let loop ((i 0))
           (or (fx= i (string-length a))
               (and (char=? (char-ascii-lowercase (string-ref a i))
                            (char-ascii-lowercase (string-ref b i)))
                    (loop (fx+ i 1)))))))

  (define (string-ascii-prefix? prefix text)
    (and (fx<= (string-length prefix) (string-length text))
         (let loop ((i 0))
           (or (fx= i (string-length prefix))
               (and (char=? (char-ascii-lowercase (string-ref prefix i))
                            (char-ascii-lowercase (string-ref text i)))
                    (loop (fx+ i 1)))))))

  (define (string-char-find text c start end)
    (let loop ((i start))
      (cond
        ((fx>= i end) #f)
        ((char=? (string-ref text i) c) i)
        (else (loop (fx+ i 1))))))

  ;; Table access

  (define (vector-pairs->hashtable entries)
    (let ((table (make-hashtable string-hash string=?)))
      (vector-for-each
        (lambda (entry) (hashtable-set! table (car entry) (cdr entry)))
        entries)
      table))

  (define (vector-strings->hashtable entries)
    (let ((table (make-hashtable string-hash string=?)))
      (vector-for-each (lambda (entry) (hashtable-set! table entry #t)) entries)
      table))

  (define html-entity-named-table
    (vector-pairs->hashtable html-entity-named-entries))

  (define html-entity-legacy-table
    (vector-strings->hashtable html-entity-legacy-names))

  (define html-entity-numeric-replacement-table
    (let ((table (make-eqv-hashtable)))
      (vector-for-each
        (lambda (entry)
          (hashtable-set! table (string->number (car entry)) (cdr entry)))
        html-entity-numeric-replacement-entries)
      table))

  (define (vector-maximum-string-length entries selector)
    (let loop ((i 0) (best 0))
      (if (fx= i (vector-length entries))
        best
        (loop (fx+ i 1)
              (fxmax best (string-length (selector (vector-ref entries i))))))))

  (define html-entity-named-maximum-length
    (vector-maximum-string-length html-entity-named-entries car))

  (define html-entity-legacy-maximum-length
    (vector-maximum-string-length html-entity-legacy-names values))

  (define (html-entity-named-ref name)
    (hashtable-ref html-entity-named-table name #f))

  (define (html-entity-legacy-name? name)
    (hashtable-ref html-entity-legacy-table name #f))

  ;; Numeric character references

  (define (string-leading-zeros-strip text)
    (let ((size (string-length text)))
      (let loop ((i 0))
        (cond
          ((fx= i size) "0")
          ((char=? (string-ref text i) #\0) (loop (fx+ i 1)))
          (else (substring text i size))))))

  (define (html-entity-numeric-decode digits hexadecimal?)
    (let ((stripped (string-leading-zeros-strip digits)))
      ;; A reference this long already exceeds the Unicode range; do not
      ;; convert an attacker-controlled digit run to a bignum.
      (if (fx> (string-length stripped) 16)
        replacement-character-string
        (let ((codepoint (string->number stripped (if hexadecimal? 16 10))))
          (cond
            ((not codepoint) replacement-character-string)
            ((> codepoint #x10FFFF) replacement-character-string)
            ((and (>= codepoint #xD800) (<= codepoint #xDFFF))
             replacement-character-string)
            (else
             (or (hashtable-ref html-entity-numeric-replacement-table codepoint #f)
                 (string (integer->char codepoint)))))))))

  ;; Named character references

  ;; Longest legacy name that is a prefix of the entity name starting at
  ;; (start + 1).  Returns (value . length) or #false.
  (define (html-entity-legacy-prefix-match text start entity-length)
    (let loop ((k (fxmin entity-length html-entity-legacy-maximum-length)))
      (if (fx< k 1)
        #f
        (let ((prefix (substring text (fx+ start 1) (fx+ start 1 k))))
          (if (html-entity-legacy-name? prefix)
            (let ((value (html-entity-named-ref prefix)))
              (if value (cons value k) (loop (fx- k 1))))
            (loop (fx- k 1)))))))

  (define (html-entity-text-decode text in-attribute?)
    (let ((text-length (string-length text))
          (port (open-output-string)))
      (define (emit string) (put-string port string))
      (let loop ((i 0))
        (if (fx>= i text-length)
          (get-output-string port)
          (let ((next-ampersand (string-char-find text #\& i text-length)))
            (cond
              ((not next-ampersand)
               (emit (substring text i text-length))
               (get-output-string port))
              (else
               (when (fx> next-ampersand i)
                 (emit (substring text i next-ampersand)))
               (let* ((start next-ampersand)
                      (after (fx+ start 1)))
                 (if (and (fx< after text-length)
                          (char=? (string-ref text after) #\#))
                   (html-numeric-reference-step text start after text-length emit loop)
                   (html-named-reference-step text start after text-length
                                              in-attribute? emit loop))))))))))

  (define (html-numeric-reference-step text start after text-length emit loop)
    (let* ((j (fx+ after 1))
           (hexadecimal?
            (and (fx< j text-length)
                 (let ((c (string-ref text j)))
                   (or (char=? c #\x) (char=? c #\X)))))
           (j (if hexadecimal? (fx+ j 1) j))
           (digit-start j)
           (j (let scan ((j j))
                (if (and (fx< j text-length)
                         (if hexadecimal?
                           (char-ascii-hexadecimal-digit? (string-ref text j))
                           (char-ascii-digit? (string-ref text j))))
                  (scan (fx+ j 1))
                  j)))
           (semicolon? (and (fx< j text-length)
                            (char=? (string-ref text j) #\;)))
           (next (if semicolon? (fx+ j 1) j))
           (digits (substring text digit-start j)))
      (cond
        ((fx> (string-length digits) 0)
         (emit (html-entity-numeric-decode digits hexadecimal?))
         (loop next))
        (else
         ;; Not a numeric reference at all; keep the source text as-is.
         (emit (substring text start next))
         (loop next)))))

  (define (html-named-reference-step text start after text-length in-attribute? emit loop)
    (let* ((j (let scan ((j after))
                (if (and (fx< j text-length)
                         (char-ascii-alphanumeric? (string-ref text j)))
                  (scan (fx+ j 1))
                  j)))
           (entity-length (fx- j after))
           (entity-name (if (fx<= entity-length html-entity-named-maximum-length)
                          (substring text after j)
                          ""))
           (semicolon? (and (fx< j text-length)
                            (char=? (string-ref text j) #\;))))
      (cond
        ((fx= entity-length 0)
         (emit "&")
         (loop (fx+ start 1)))
        ;; Exact match, semicolon terminated.
        ((and semicolon? (html-entity-named-ref entity-name))
         => (lambda (value)
              (emit value)
              (loop (fx+ j 1))))
        (else
         (let ((prefix-match
                (and semicolon?
                     (not in-attribute?)
                     (html-entity-legacy-prefix-match text start entity-length))))
           (cond
             ;; Semicolon present but no exact match: longest legacy prefix
             ;; wins outside attributes ("&notit;" -> "\xAC;it;").
             (prefix-match
              (emit (car prefix-match))
              (loop (fx+ start 1 (cdr prefix-match))))
             ((and (html-entity-legacy-name? entity-name)
                   (html-entity-named-ref entity-name))
              => (lambda (value)
                   (let ((next-char (and (fx< j text-length) (string-ref text j))))
                     (if (and in-attribute?
                              next-char
                              (or (char-ascii-alphanumeric? next-char)
                                  (char=? next-char #\=)))
                       (begin (emit "&") (loop (fx+ start 1)))
                       (begin (emit value) (loop j))))))
             (else
              (let ((prefix-match
                     (html-entity-legacy-prefix-match text start entity-length)))
                (cond
                  ((and prefix-match in-attribute?)
                   ;; Ambiguous ampersand inside an attribute value: leave it.
                   (emit "&")
                   (loop (fx+ start 1)))
                  (prefix-match
                   (emit (car prefix-match))
                   (loop (fx+ start 1 (cdr prefix-match))))
                  (semicolon?
                   (emit (substring text start (fx+ j 1)))
                   (loop (fx+ j 1)))
                  (else
                   (emit "&")
                   (loop (fx+ start 1))))))))))))

  ;; ====================================================================
  ;; Section 3 -- scanner
  ;; ====================================================================
  ;; Layer 2 -- pure, stateless string search helpers, ported from
  ;; submodules/justhtml/src/justhtml/parser/scanner.py.
  ;;
  ;; Every procedure takes explicit start/end bounds into the input string
  ;; and returns an index or #false; nothing here holds state.

  (define (html-space-character? c)
    (or (char=? c #\space) (char=? c #\tab) (char=? c #\newline)
        (char=? c #\page) (char=? c #\return)))

  ;; TAG_END_NAME_STOP = SPACE + "/>"
  (define (html-tag-end-name-stop-character? c)
    (or (html-space-character? c) (char=? c #\/) (char=? c #\>)))

  (define (html-scanner-ascii-startswith? text needle start end)
    (let ((stop (fx+ start (string-length needle))))
      (and (fx<= stop end)
           (let loop ((i 0))
             (or (fx= i (string-length needle))
                 (and (char=? (char-ascii-lowercase (string-ref text (fx+ start i)))
                              (char-ascii-lowercase (string-ref needle i)))
                      (loop (fx+ i 1))))))))

  ;; Case-insensitive forward search; index of the first match or #false.
  (define (html-scanner-ascii-find text needle start end)
    (let ((needle-length (string-length needle)))
      (let loop ((i start))
        (cond
          ((fx> (fx+ i needle-length) end) #f)
          ((html-scanner-ascii-startswith? text needle i end) i)
          (else (loop (fx+ i 1)))))))

  ;; Case-insensitive backward search; index of the last match or #false.
  (define (html-scanner-ascii-rfind text needle start end)
    (let ((needle-length (string-length needle)))
      (let loop ((i (fx- end needle-length)))
        (cond
          ((fx< i start) #f)
          ((html-scanner-ascii-startswith? text needle i end) i)
          (else (loop (fx- i 1)))))))

  ;; Index of the ">" that ends a tag, skipping ">" inside quoted attribute
  ;; values, or #false when the tag is unterminated.
  (define (html-scanner-tag-end-find text position end)
    (let loop ((position position) (quote-character #f))
      (if (fx>= position end)
        #f
        (let ((c (string-ref text position)))
          (cond
            (quote-character
             (loop (fx+ position 1)
                   (if (char=? c quote-character) #f quote-character)))
            ((or (char=? c #\") (char=? c #\'))
             (loop (fx+ position 1) c))
            ((char=? c #\>) position)
            (else (loop (fx+ position 1) #f)))))))

  ;; Find "</name" terminated by a space, "/" or ">".  Returns two values:
  ;; the index of "<" (or #false when no end tag is present) and the
  ;; position at which parsing resumes.
  (define (html-scanner-rawtext-end-tag-find text name position end)
    (let* ((needle (string-append "</" name))
           (needle-length (string-length needle)))
      (let loop ((search position))
        (let ((close (html-scanner-ascii-find text needle search end)))
          (cond
            ((not close) (values #f end))
            (else
             (let ((after-name (fx+ close needle-length)))
               (cond
                 ((and (fx< after-name end)
                       (not (html-tag-end-name-stop-character?
                             (string-ref text after-name))))
                  (loop after-name))
                 (else
                  (let ((tag-end (html-scanner-tag-end-find text after-name end)))
                    (cond
                      (tag-end (values close (fx+ tag-end 1)))
                      ;; At EOF the end tag is still emitted with its
                      ;; attributes dropped, so the raw text ends here.  Only
                      ;; a bare "</name" at EOF stays raw text.
                      ((fx< after-name end) (values close end))
                      (else (loop after-name)))))))))))))

  ;; Find the "</script" that ends script data, honouring the
  ;; script-data-escaped and script-data-double-escaped states.
  (define (html-scanner-script-end-tag-find text position end)
    (let loop ((search position) (escaped? #f) (double-escaped? #f))
      (call-with-values
        (lambda () (html-scanner-rawtext-end-tag-find text "script" search end))
        (lambda (close next-position)
          (cond
            ((not close) (values #f end))
            ((not escaped?)
             (let ((comment-start (html-scanner-ascii-find text "<!--" search close)))
               (if (not comment-start)
                 (values close next-position)
                 ;; After "<!--" the tokenizer sits in
                 ;; script-data-escaped-dash-dash, so the two trailing dashes
                 ;; already count toward a closing "-->".
                 (loop (fx+ comment-start 2) #t #f))))
            (else
             (let* ((script-start
                     (and (not double-escaped?)
                          (html-scanner-script-start-marker-find text search close end)))
                    (comment-end (html-scanner-ascii-find text "-->" search close)))
               (cond
                 ((and comment-end
                       (fx< comment-end close)
                       (or double-escaped?
                           (not script-start)
                           (fx< comment-end script-start)))
                  (loop (fx+ comment-end 3) #f #f))
                 ((and script-start (fx< script-start close))
                  (loop (fx+ script-start 7) #t #t))
                 (double-escaped?
                  (let ((later-end (html-scanner-ascii-find
                                    text "</script" (fx+ close 8) next-position)))
                    (if (and later-end
                             (let ((after-name (fx+ later-end 8)))
                               (or (fx>= after-name end)
                                   (html-tag-end-name-stop-character?
                                    (string-ref text after-name)))))
                      (loop (fx+ close 8) #t #f)
                      (loop next-position #t #f))))
                 (else (values close next-position))))))))))

  ;; Index of a "<script" marker terminated by a space, "/" or ">".
  ;; `end` bounds where the marker may start, `text-end` bounds the real
  ;; input so the terminator is checked against the actual next character.
  (define (html-scanner-script-start-marker-find text position end text-end)
    (let ((needle "<script"))
      (let loop ((search position))
        (let ((start (html-scanner-ascii-find text needle search end)))
          (cond
            ((not start) #f)
            (else
             (let ((after-name (fx+ start 7)))
               (if (or (fx>= after-name text-end)
                       (html-tag-end-name-stop-character?
                        (string-ref text after-name)))
                 start
                 (loop after-name)))))))))

  ;; ====================================================================
  ;; Section 4 -- tokenizer
  ;; ====================================================================
  ;; Layer 3 -- the WHATWG HTML tokenizer (spec 13.2.5).
  ;;
  ;; Tag, attribute, comment, DOCTYPE and CDATA states are written out as
  ;; named states of the spec's own state machine.  The text-content states
  ;; (RCDATA, RAWTEXT, script data and their escaped variants) are driven by
  ;; layer 2's scanner instead of by eighteen character-at-a-time sub-states:
  ;; the scanner locates the appropriate end tag exactly as justhtml's engine
  ;; does, the run in front of it is emitted as one character token, and the
  ;; end tag itself is then tokenized by the ordinary tag states.

  (define replacement-character (integer->char #xFFFD))

  ;; Token records -- one per kind.

  (define-record-type (token-start-tag token-start-tag-make token-start-tag?)
    (fields (immutable name token-start-tag-name)
            (immutable attributes token-start-tag-attributes)
            (immutable self-closing? token-start-tag-self-closing?)))

  (define-record-type (token-end-tag token-end-tag-make token-end-tag?)
    (fields (immutable name token-end-tag-name)))

  (define-record-type (token-character token-character-make token-character?)
    (fields (immutable text token-character-text)))

  (define-record-type (token-comment token-comment-make token-comment?)
    (fields (immutable text token-comment-text)))

  (define-record-type (token-doctype token-doctype-make token-doctype?)
    (fields (immutable name token-doctype-name)
            (immutable public-id token-doctype-public-id)
            (immutable system-id token-doctype-system-id)
            (immutable force-quirks? token-doctype-force-quirks?)))

  (define-record-type (token-end-of-file token-end-of-file-make token-end-of-file?)
    (fields))

  ;; "<?...>" is a bogus comment per the spec; justhtml -- and this port --
  ;; keep it as a processing instruction instead, which is what the
  ;; tokenizer_recovery.dat fixtures expect.
  (define-record-type (token-processing-instruction
                        token-processing-instruction-make
                        token-processing-instruction?)
    (fields (immutable target token-processing-instruction-target)
            (immutable data token-processing-instruction-data)))

  ;; Input preprocessing (spec 13.2.3.5): drop a leading BOM, normalize CRLF
  ;; and lone CR to LF.

  (define (html-source-preprocess text)
    (let* ((size (string-length text))
           (start (if (and (fx> size 0)
                           (char=? (string-ref text 0) (integer->char #xFEFF)))
                    1
                    0))
           (port (open-output-string)))
      (let loop ((i start))
        (if (fx>= i size)
          (get-output-string port)
          (let ((c (string-ref text i)))
            (cond
              ((char=? c #\return)
               (write-char #\newline port)
               (if (and (fx< (fx+ i 1) size)
                        (char=? (string-ref text (fx+ i 1)) #\newline))
                 (loop (fx+ i 2))
                 (loop (fx+ i 1))))
              (else
               (write-char c port)
               (loop (fx+ i 1)))))))))

  ;; Tokenizer state

  (define-record-type (html-tokenizer html-tokenizer-new html-tokenizer?)
    (fields (immutable text tk-text)
            (immutable size tk-size)
            (mutable position tk-position tk-position-set!)
            (mutable state tk-state tk-state-set!)
            (mutable queue tk-queue tk-queue-set!)
            (mutable finished? tk-finished? tk-finished-set!)
            (mutable last-start-tag tk-last-start-tag tk-last-start-tag-set!)
            (mutable foreign? tk-foreign? tk-foreign-set!)
            (mutable scripting? tk-scripting? tk-scripting-set!)
            (mutable tag-name tk-tag-name tk-tag-name-set!)
            (mutable tag-end? tk-tag-end? tk-tag-end-set!)
            (mutable tag-self-closing? tk-tag-self-closing? tk-tag-self-closing-set!)
            (mutable attributes tk-attributes tk-attributes-set!)
            (mutable attribute-name tk-attribute-name tk-attribute-name-set!)
            (mutable attribute-value tk-attribute-value tk-attribute-value-set!)
            (mutable comment tk-comment tk-comment-set!)
            (mutable doctype-name tk-doctype-name tk-doctype-name-set!)
            (mutable doctype-public tk-doctype-public tk-doctype-public-set!)
            (mutable doctype-system tk-doctype-system tk-doctype-system-set!)
            (mutable doctype-quirks? tk-doctype-quirks? tk-doctype-quirks-set!)))

  (define (html-tokenizer-make text)
    (html-tokenizer-new text (string-length text) 0 'data '() #f #f #f #t
                        #f #f #f '() #f #f #f #f #f #f #f))

  (define (html-tokenizer-state-set! tokenizer state)
    (tk-state-set! tokenizer state))

  (define (html-tokenizer-last-start-tag-set! tokenizer name)
    (tk-last-start-tag-set! tokenizer name))

  (define (html-tokenizer-foreign-set! tokenizer foreign?)
    (tk-foreign-set! tokenizer foreign?))

  (define (html-tokenizer-scripting-set! tokenizer scripting?)
    (tk-scripting-set! tokenizer scripting?))

  (define (token-emit! tokenizer token)
    (tk-queue-set! tokenizer (append (tk-queue tokenizer) (list token))))

  (define (character-emit! tokenizer text)
    (unless (fx= (string-length text) 0)
      (token-emit! tokenizer (token-character-make text))))

  (define (end-of-file-emit! tokenizer)
    (token-emit! tokenizer (token-end-of-file-make))
    (tk-finished-set! tokenizer #t))

  ;; Return the next token, or #false once the end-of-file token has been
  ;; consumed.
  (define (html-tokenizer-next tokenizer)
    (let loop ()
      (let ((queue (tk-queue tokenizer)))
        (cond
          ((pair? queue)
           (tk-queue-set! tokenizer (cdr queue))
           (car queue))
          ((tk-finished? tokenizer) #f)
          (else
           (tokenizer-step tokenizer)
           (loop))))))

  ;; Content model of a start tag name (justhtml engine.py lines 78-80).
  (define (html-tokenizer-content-state-for-tag name scripting?)
    (cond
      ((or (string=? name "title") (string=? name "textarea")) 'rcdata)
      ((string=? name "script") 'script-data)
      ((or (string=? name "style") (string=? name "xmp")
           (string=? name "iframe") (string=? name "noembed")
           (string=? name "noframes"))
       'rawtext)
      ((string=? name "noscript") (if scripting? 'rawtext 'data))
      ((string=? name "plaintext") 'plaintext)
      (else 'data)))

  ;; Current-token accumulators

  (define (tag-start! tokenizer end?)
    (tk-tag-name-set! tokenizer (open-output-string))
    (tk-tag-end-set! tokenizer end?)
    (tk-tag-self-closing-set! tokenizer #f)
    (tk-attributes-set! tokenizer '())
    (tk-attribute-name-set! tokenizer #f)
    (tk-attribute-value-set! tokenizer #f))

  (define (tag-name-append! tokenizer c)
    (write-char c (tk-tag-name tokenizer)))

  (define (attribute-finish! tokenizer)
    (let ((name-port (tk-attribute-name tokenizer)))
      (when name-port
        (let* ((name (get-output-string name-port))
               (value-port (tk-attribute-value tokenizer))
               (raw (if value-port (get-output-string value-port) "")))
          ;; First attribute wins on duplicates.
          (unless (assoc name (tk-attributes tokenizer))
            (tk-attributes-set!
              tokenizer
              (append (tk-attributes tokenizer)
                      (list (cons name (html-entity-text-decode raw #t))))))))
      (tk-attribute-name-set! tokenizer #f)
      (tk-attribute-value-set! tokenizer #f)))

  (define (attribute-start! tokenizer)
    (attribute-finish! tokenizer)
    (tk-attribute-name-set! tokenizer (open-output-string))
    (tk-attribute-value-set! tokenizer #f))

  (define (attribute-name-append! tokenizer c)
    (write-char c (tk-attribute-name tokenizer)))

  (define (attribute-value-port tokenizer)
    (or (tk-attribute-value tokenizer)
        (let ((port (open-output-string)))
          (tk-attribute-value-set! tokenizer port)
          port)))

  (define (attribute-value-append! tokenizer c)
    (write-char c (attribute-value-port tokenizer)))

  (define (tag-emit! tokenizer)
    (attribute-finish! tokenizer)
    (let ((name (get-output-string (tk-tag-name tokenizer))))
      (cond
        ((tk-tag-end? tokenizer)
         ;; End tags carry neither attributes nor a self-closing flag.
         (token-emit! tokenizer (token-end-tag-make name))
         (tk-state-set! tokenizer 'data))
        (else
         (token-emit! tokenizer
                      (token-start-tag-make name
                                            (tk-attributes tokenizer)
                                            (tk-tag-self-closing? tokenizer)))
         (tk-last-start-tag-set! tokenizer name)
         (tk-state-set! tokenizer
                        (if (tk-foreign? tokenizer)
                          'data
                          (html-tokenizer-content-state-for-tag
                            name (tk-scripting? tokenizer))))))))

  (define (comment-start! tokenizer)
    (tk-comment-set! tokenizer (open-output-string)))

  (define (comment-append! tokenizer c)
    (write-char c (tk-comment tokenizer)))

  (define (comment-append-string! tokenizer text)
    (put-string (tk-comment tokenizer) text))

  (define (comment-emit! tokenizer)
    (token-emit! tokenizer
                 (token-comment-make (get-output-string (tk-comment tokenizer)))))

  (define (doctype-start! tokenizer)
    (tk-doctype-name-set! tokenizer #f)
    (tk-doctype-public-set! tokenizer #f)
    (tk-doctype-system-set! tokenizer #f)
    (tk-doctype-quirks-set! tokenizer #f))

  (define (doctype-emit! tokenizer)
    (token-emit! tokenizer
                 (token-doctype-make
                   (let ((port (tk-doctype-name tokenizer)))
                     (and port (get-output-string port)))
                   (let ((port (tk-doctype-public tokenizer)))
                     (and port (get-output-string port)))
                   (let ((port (tk-doctype-system tokenizer)))
                     (and port (get-output-string port)))
                   (tk-doctype-quirks? tokenizer))))

  ;; Character classification used by the tag states

  (define (space-character? c)
    (or (char=? c #\tab) (char=? c #\newline)
        (char=? c #\page) (char=? c #\space)))

  (define (nul->replacement c)
    (if (char=? c #\nul) replacement-character c))

  (define (string-nul-replace text)
    (if (let loop ((i 0))
          (cond ((fx>= i (string-length text)) #f)
                ((char=? (string-ref text i) #\nul) #t)
                (else (loop (fx+ i 1)))))
      (list->string (map nul->replacement (string->list text)))
      text))

  ;; The state machine

  (define (tokenizer-step tokenizer)
    (case (tk-state tokenizer)
      ((data) (state-data tokenizer))
      ((rcdata) (state-text-content tokenizer 'rcdata))
      ((rawtext) (state-text-content tokenizer 'rawtext))
      ((script-data) (state-text-content tokenizer 'script-data))
      ((plaintext) (state-plaintext tokenizer))
      ((tag-open) (state-tag-open tokenizer))
      ((end-tag-open) (state-end-tag-open tokenizer))
      ((tag-name) (state-tag-name tokenizer))
      ((before-attribute-name) (state-before-attribute-name tokenizer))
      ((attribute-name) (state-attribute-name tokenizer))
      ((after-attribute-name) (state-after-attribute-name tokenizer))
      ((before-attribute-value) (state-before-attribute-value tokenizer))
      ((attribute-value-double-quoted)
       (state-attribute-value-quoted tokenizer #\"))
      ((attribute-value-single-quoted)
       (state-attribute-value-quoted tokenizer #\'))
      ((attribute-value-unquoted) (state-attribute-value-unquoted tokenizer))
      ((after-attribute-value-quoted) (state-after-attribute-value-quoted tokenizer))
      ((self-closing-start-tag) (state-self-closing-start-tag tokenizer))
      ((bogus-comment) (state-bogus-comment tokenizer))
      ((processing-instruction) (state-processing-instruction tokenizer))
      ((markup-declaration-open) (state-markup-declaration-open tokenizer))
      ((comment-start) (state-comment-start tokenizer))
      ((comment-start-dash) (state-comment-start-dash tokenizer))
      ((comment) (state-comment tokenizer))
      ((comment-less-than-sign) (state-comment-less-than-sign tokenizer))
      ((comment-less-than-sign-bang) (state-comment-less-than-sign-bang tokenizer))
      ((comment-less-than-sign-bang-dash)
       (state-comment-less-than-sign-bang-dash tokenizer))
      ((comment-less-than-sign-bang-dash-dash)
       (state-comment-less-than-sign-bang-dash-dash tokenizer))
      ((comment-end-dash) (state-comment-end-dash tokenizer))
      ((comment-end) (state-comment-end tokenizer))
      ((comment-end-bang) (state-comment-end-bang tokenizer))
      ((doctype) (state-doctype tokenizer))
      ((before-doctype-name) (state-before-doctype-name tokenizer))
      ((doctype-name) (state-doctype-name tokenizer))
      ((after-doctype-name) (state-after-doctype-name tokenizer))
      ((after-doctype-public-keyword) (state-after-doctype-keyword tokenizer 'public))
      ((after-doctype-system-keyword) (state-after-doctype-keyword tokenizer 'system))
      ((before-doctype-public-identifier)
       (state-before-doctype-identifier tokenizer 'public))
      ((before-doctype-system-identifier)
       (state-before-doctype-identifier tokenizer 'system))
      ((doctype-public-identifier-double-quoted)
       (state-doctype-identifier tokenizer 'public #\"))
      ((doctype-public-identifier-single-quoted)
       (state-doctype-identifier tokenizer 'public #\'))
      ((doctype-system-identifier-double-quoted)
       (state-doctype-identifier tokenizer 'system #\"))
      ((doctype-system-identifier-single-quoted)
       (state-doctype-identifier tokenizer 'system #\'))
      ((after-doctype-public-identifier)
       (state-after-doctype-public-identifier tokenizer))
      ((between-doctype-public-and-system-identifiers)
       (state-between-doctype-identifiers tokenizer))
      ((after-doctype-system-identifier)
       (state-after-doctype-system-identifier tokenizer))
      ((bogus-doctype) (state-bogus-doctype tokenizer))
      ((cdata-section) (state-cdata-section tokenizer))
      (else (error 'tokenizer-step "unknown tokenizer state" (tk-state tokenizer)))))

  (define (at-end? tokenizer)
    (fx>= (tk-position tokenizer) (tk-size tokenizer)))

  (define (peek tokenizer)
    (string-ref (tk-text tokenizer) (tk-position tokenizer)))

  (define (advance! tokenizer)
    (tk-position-set! tokenizer (fx+ (tk-position tokenizer) 1)))

  (define (consume! tokenizer)
    (let ((c (peek tokenizer)))
      (advance! tokenizer)
      c))

  ;; 13.2.5.1 data state

  (define (state-data tokenizer)
    (if (at-end? tokenizer)
      (end-of-file-emit! tokenizer)
      (let* ((text (tk-text tokenizer))
             (size (tk-size tokenizer))
             (start (tk-position tokenizer))
             (stop (let loop ((i start))
                     (cond
                       ((fx>= i size) size)
                       ((char=? (string-ref text i) #\<) i)
                       (else (loop (fx+ i 1)))))))
        (cond
          ((fx> stop start)
           ;; U+0000 is passed through unchanged in the data state; the tree
           ;; construction stage drops it.
           (character-emit! tokenizer
                            (html-entity-text-decode (substring text start stop) #f))
           (tk-position-set! tokenizer stop))
          (else
           (advance! tokenizer)
           (tk-state-set! tokenizer 'tag-open))))))

  ;; RCDATA / RAWTEXT / script data, driven by the layer 2 scanner.

  (define (state-text-content tokenizer kind)
    (let* ((text (tk-text tokenizer))
           (size (tk-size tokenizer))
           (start (tk-position tokenizer))
           (name (tk-last-start-tag tokenizer)))
      (call-with-values
        (lambda ()
          ;; Without a last start tag -- fragment parsing seeded directly into
          ;; a text-content state -- no end tag is ever the appropriate one.
          (cond
            ((not name) (values #f size))
            ((eq? kind 'script-data)
             (html-scanner-script-end-tag-find text start size))
            (else (html-scanner-rawtext-end-tag-find text name start size))))
        (lambda (close next)
          (let* ((stop (or close size))
                 (raw (substring text start stop))
                 (content (if (eq? kind 'rcdata)
                            (html-entity-text-decode (string-nul-replace raw) #f)
                            (string-nul-replace raw))))
            (character-emit! tokenizer content)
            (cond
              (close
               ;; Let the ordinary tag states tokenize the end tag itself.
               (tk-position-set! tokenizer close)
               (tk-state-set! tokenizer 'data))
              (else
               (tk-position-set! tokenizer size)
               (tk-state-set! tokenizer 'data))))))))

  (define (state-plaintext tokenizer)
    (let* ((text (tk-text tokenizer))
           (size (tk-size tokenizer))
           (start (tk-position tokenizer)))
      (if (fx>= start size)
        (end-of-file-emit! tokenizer)
        (begin
          (character-emit! tokenizer (string-nul-replace (substring text start size)))
          (tk-position-set! tokenizer size)))))

  ;; 13.2.5.6 tag open state

  (define (state-tag-open tokenizer)
    (cond
      ((at-end? tokenizer)
       (character-emit! tokenizer "<")
       (end-of-file-emit! tokenizer))
      (else
       (let ((c (peek tokenizer)))
         (cond
           ((char=? c #\!)
            (advance! tokenizer)
            (tk-state-set! tokenizer 'markup-declaration-open))
           ((char=? c #\/)
            (advance! tokenizer)
            (tk-state-set! tokenizer 'end-tag-open))
           ((char-ascii-alphabetic? c)
            (tag-start! tokenizer #f)
            (tk-state-set! tokenizer 'tag-name))
           ((char=? c #\?)
            (tk-state-set! tokenizer 'processing-instruction))
           ((char=? c #\nul)
            ;; justhtml emits "<" plus the replacement character here rather
            ;; than reconsuming the NUL in the data state.
            (advance! tokenizer)
            (character-emit! tokenizer (string #\< replacement-character))
            (tk-state-set! tokenizer 'data))
           (else
            (character-emit! tokenizer "<")
            (tk-state-set! tokenizer 'data)))))))

  ;; 13.2.5.7 end tag open state

  (define (state-end-tag-open tokenizer)
    (cond
      ((at-end? tokenizer)
       (character-emit! tokenizer "</")
       (end-of-file-emit! tokenizer))
      (else
       (let ((c (peek tokenizer)))
         (cond
           ((char-ascii-alphabetic? c)
            (tag-start! tokenizer #t)
            (tk-state-set! tokenizer 'tag-name))
           ((char=? c #\>)
            (advance! tokenizer)
            (tk-state-set! tokenizer 'data))
           (else
            (comment-start! tokenizer)
            (tk-state-set! tokenizer 'bogus-comment)))))))

  ;; 13.2.5.8 tag name state

  (define (state-tag-name tokenizer)
    (cond
      ((at-end? tokenizer) (end-of-file-emit! tokenizer))
      (else
       (let ((c (consume! tokenizer)))
         (cond
           ((space-character? c) (tk-state-set! tokenizer 'before-attribute-name))
           ((char=? c #\/) (tk-state-set! tokenizer 'self-closing-start-tag))
           ((char=? c #\>) (tag-emit! tokenizer))
           (else (tag-name-append! tokenizer
                                   (char-ascii-lowercase (nul->replacement c)))))))))

  ;; 13.2.5.32 before attribute name state

  (define (state-before-attribute-name tokenizer)
    (cond
      ((at-end? tokenizer) (tk-state-set! tokenizer 'after-attribute-name))
      (else
       (let ((c (peek tokenizer)))
         (cond
           ((space-character? c) (advance! tokenizer))
           ((or (char=? c #\/) (char=? c #\>))
            (tk-state-set! tokenizer 'after-attribute-name))
           ((char=? c #\=)
            (advance! tokenizer)
            (attribute-start! tokenizer)
            (attribute-name-append! tokenizer c)
            (tk-state-set! tokenizer 'attribute-name))
           (else
            (attribute-start! tokenizer)
            (tk-state-set! tokenizer 'attribute-name)))))))

  ;; 13.2.5.33 attribute name state

  (define (state-attribute-name tokenizer)
    (cond
      ((at-end? tokenizer) (tk-state-set! tokenizer 'after-attribute-name))
      (else
       (let ((c (peek tokenizer)))
         (cond
           ((or (space-character? c) (char=? c #\/) (char=? c #\>))
            (tk-state-set! tokenizer 'after-attribute-name))
           ((char=? c #\=)
            (advance! tokenizer)
            (tk-state-set! tokenizer 'before-attribute-value))
           (else
            (advance! tokenizer)
            (attribute-name-append! tokenizer
                                    (char-ascii-lowercase (nul->replacement c)))))))))

  ;; 13.2.5.34 after attribute name state

  (define (state-after-attribute-name tokenizer)
    (cond
      ((at-end? tokenizer) (end-of-file-emit! tokenizer))
      (else
       (let ((c (peek tokenizer)))
         (cond
           ((space-character? c) (advance! tokenizer))
           ((char=? c #\/)
            (advance! tokenizer)
            (tk-state-set! tokenizer 'self-closing-start-tag))
           ((char=? c #\=)
            (advance! tokenizer)
            (tk-state-set! tokenizer 'before-attribute-value))
           ((char=? c #\>)
            (advance! tokenizer)
            (tag-emit! tokenizer))
           (else
            (attribute-start! tokenizer)
            (tk-state-set! tokenizer 'attribute-name)))))))

  ;; 13.2.5.35 before attribute value state

  (define (state-before-attribute-value tokenizer)
    (cond
      ((at-end? tokenizer) (tk-state-set! tokenizer 'attribute-value-unquoted))
      (else
       (let ((c (peek tokenizer)))
         (cond
           ((space-character? c) (advance! tokenizer))
           ((char=? c #\")
            (advance! tokenizer)
            (attribute-value-port tokenizer)
            (tk-state-set! tokenizer 'attribute-value-double-quoted))
           ((char=? c #\')
            (advance! tokenizer)
            (attribute-value-port tokenizer)
            (tk-state-set! tokenizer 'attribute-value-single-quoted))
           ((char=? c #\>)
            (advance! tokenizer)
            (tag-emit! tokenizer))
           (else
            (attribute-value-port tokenizer)
            (tk-state-set! tokenizer 'attribute-value-unquoted)))))))

  ;; 13.2.5.36/37 attribute value (double|single) quoted states

  (define (state-attribute-value-quoted tokenizer quote-character)
    (cond
      ((at-end? tokenizer) (end-of-file-emit! tokenizer))
      (else
       (let ((c (consume! tokenizer)))
         (cond
           ((char=? c quote-character)
            (tk-state-set! tokenizer 'after-attribute-value-quoted))
           (else (attribute-value-append! tokenizer (nul->replacement c))))))))

  ;; 13.2.5.38 attribute value (unquoted) state

  (define (state-attribute-value-unquoted tokenizer)
    (cond
      ((at-end? tokenizer) (end-of-file-emit! tokenizer))
      (else
       (let ((c (consume! tokenizer)))
         (cond
           ((space-character? c) (tk-state-set! tokenizer 'before-attribute-name))
           ((char=? c #\>) (tag-emit! tokenizer))
           (else (attribute-value-append! tokenizer (nul->replacement c))))))))

  ;; 13.2.5.39 after attribute value (quoted) state

  (define (state-after-attribute-value-quoted tokenizer)
    (cond
      ((at-end? tokenizer) (end-of-file-emit! tokenizer))
      (else
       (let ((c (peek tokenizer)))
         (cond
           ((space-character? c)
            (advance! tokenizer)
            (tk-state-set! tokenizer 'before-attribute-name))
           ((char=? c #\/)
            (advance! tokenizer)
            (tk-state-set! tokenizer 'self-closing-start-tag))
           ((char=? c #\>)
            (advance! tokenizer)
            (tag-emit! tokenizer))
           (else (tk-state-set! tokenizer 'before-attribute-name)))))))

  ;; 13.2.5.40 self-closing start tag state

  (define (state-self-closing-start-tag tokenizer)
    (cond
      ((at-end? tokenizer) (end-of-file-emit! tokenizer))
      (else
       (let ((c (peek tokenizer)))
         (cond
           ((char=? c #\>)
            (advance! tokenizer)
            (tk-tag-self-closing-set! tokenizer #t)
            (tag-emit! tokenizer))
           (else (tk-state-set! tokenizer 'before-attribute-name)))))))

  ;; 13.2.5.41 bogus comment state

  (define (state-bogus-comment tokenizer)
    (cond
      ((at-end? tokenizer)
       (comment-emit! tokenizer)
       (end-of-file-emit! tokenizer))
      (else
       (let ((c (consume! tokenizer)))
         (cond
           ((char=? c #\>)
            (comment-emit! tokenizer)
            (tk-state-set! tokenizer 'data))
           (else (comment-append! tokenizer (nul->replacement c))))))))

  ;; Processing instructions.  The spec makes "<?" a bogus comment; justhtml
  ;; recognises an XML-style processing instruction instead when the content
  ;; starts with a name and the tag is terminated, and otherwise falls back to
  ;; a comment or to no token at all (engine.py, _processing_instruction_data).

  (define (pi-name-start? c)
    (or (char=? c #\_) (char-ascii-alphabetic? c)))

  (define (pi-name-char? c)
    (or (char=? c #\_) (char=? c #\-) (char-ascii-alphanumeric? c)))

  (define (pi-target-scan text start end)
    (let loop ((i start))
      (if (and (fx< i end) (pi-name-char? (string-ref text i)))
        (loop (fx+ i 1))
        i)))

  (define (pi-xml-target? target)
    (and (fx>= (string-length target) 3)
         (string-ascii-equal? (substring target 0 3) "xml")))

  ;; Returns (values target data) or (values #false #false).
  (define (pi-content-parse text content-start content-end)
    (cond
      ((fx>= content-start content-end) (values #f #f))
      ((not (pi-name-start? (string-ref text content-start))) (values #f #f))
      (else
       (let* ((after (pi-target-scan text (fx+ content-start 1) content-end))
              (target (substring text content-start after)))
         (cond
           ((pi-xml-target? target) (values #f #f))
           ((fx= after content-end) (values target ""))
           (else
            (let ((c (string-ref text after)))
              (cond
                ((char=? c #\?) (values target (pi-data-take text after content-end)))
                ((html-space-character? c)
                 (let loop ((i (fx+ after 1)))
                   (if (and (fx< i content-end)
                            (html-space-character? (string-ref text i)))
                     (loop (fx+ i 1))
                     (values target (pi-data-take text i content-end)))))
                (else (values #f #f))))))))))

  (define (pi-data-take text start end)
    (let* ((raw (substring text start end))
           (size (string-length raw))
           (trimmed (if (and (fx> size 0) (char=? (string-ref raw (fx- size 1)) #\?))
                      (substring raw 0 (fx- size 1))
                      raw)))
      (string-nul-replace trimmed)))

  (define (state-processing-instruction tokenizer)
    (let* ((text (tk-text tokenizer))
           (size (tk-size tokenizer))
           (start (tk-position tokenizer))
           (close (let loop ((i (fx+ start 1)))
                    (cond
                      ((fx>= i size) #f)
                      ((char=? (string-ref text i) #\>) i)
                      (else (loop (fx+ i 1)))))))
      (cond
        ((not close)
         (cond
           ((fx>= (fx+ start 1) size) #f)
           (else
            (let ((c (string-ref text (fx+ start 1))))
              (cond
                ((pi-name-start? c)
                 (let ((target (substring text (fx+ start 1)
                                          (pi-target-scan text (fx+ start 2) size))))
                   (when (pi-xml-target? target)
                     (token-emit! tokenizer
                                  (token-comment-make
                                    (string-nul-replace (substring text start size)))))))
                ((not (html-space-character? c))
                 (when (char=? c #\#)
                   (token-emit! tokenizer
                                (token-comment-make
                                  (string-nul-replace (substring text start size))))))
                (else
                 (token-emit! tokenizer
                              (token-comment-make
                                (string-nul-replace (substring text start size)))))))))
         (tk-position-set! tokenizer size)
         (tk-state-set! tokenizer 'data))
        (else
         (call-with-values
           (lambda () (pi-content-parse text (fx+ start 1) close))
           (lambda (target data)
             (if target
               (token-emit! tokenizer (token-processing-instruction-make target data))
               (token-emit! tokenizer
                            (token-comment-make
                              (string-nul-replace (substring text start close)))))))
         (tk-position-set! tokenizer (fx+ close 1))
         (tk-state-set! tokenizer 'data)))))

  ;; 13.2.5.42 markup declaration open state

  (define (state-markup-declaration-open tokenizer)
    (let ((text (tk-text tokenizer))
          (size (tk-size tokenizer))
          (position (tk-position tokenizer)))
      (cond
        ((html-scanner-ascii-startswith? text "--" position size)
         (tk-position-set! tokenizer (fx+ position 2))
         (comment-start! tokenizer)
         (tk-state-set! tokenizer 'comment-start))
        ((html-scanner-ascii-startswith? text "doctype" position size)
         (tk-position-set! tokenizer (fx+ position 7))
         (tk-state-set! tokenizer 'doctype))
        ((html-scanner-ascii-startswith? text "[CDATA[" position size)
         (cond
           ((tk-foreign? tokenizer)
            (tk-position-set! tokenizer (fx+ position 7))
            (tk-state-set! tokenizer 'cdata-section))
           (else
            (tk-position-set! tokenizer (fx+ position 7))
            (comment-start! tokenizer)
            (comment-append-string! tokenizer "[CDATA[")
            (tk-state-set! tokenizer 'bogus-comment))))
        (else
         (comment-start! tokenizer)
         (tk-state-set! tokenizer 'bogus-comment)))))

  ;; 13.2.5.43-51 comment states

  (define (state-comment-start tokenizer)
    (cond
      ((at-end? tokenizer) (tk-state-set! tokenizer 'comment))
      (else
       (let ((c (peek tokenizer)))
         (cond
           ((char=? c #\-)
            (advance! tokenizer)
            (tk-state-set! tokenizer 'comment-start-dash))
           ((char=? c #\>)
            (advance! tokenizer)
            (comment-emit! tokenizer)
            (tk-state-set! tokenizer 'data))
           (else (tk-state-set! tokenizer 'comment)))))))

  (define (state-comment-start-dash tokenizer)
    (cond
      ((at-end? tokenizer)
       (comment-emit! tokenizer)
       (end-of-file-emit! tokenizer))
      (else
       (let ((c (peek tokenizer)))
         (cond
           ((char=? c #\-)
            (advance! tokenizer)
            (tk-state-set! tokenizer 'comment-end))
           ((char=? c #\>)
            (advance! tokenizer)
            (comment-emit! tokenizer)
            (tk-state-set! tokenizer 'data))
           (else
            (comment-append! tokenizer #\-)
            (tk-state-set! tokenizer 'comment)))))))

  (define (state-comment tokenizer)
    (cond
      ((at-end? tokenizer)
       (comment-emit! tokenizer)
       (end-of-file-emit! tokenizer))
      (else
       (let ((c (consume! tokenizer)))
         (cond
           ((char=? c #\<)
            (comment-append! tokenizer c)
            (tk-state-set! tokenizer 'comment-less-than-sign))
           ((char=? c #\-) (tk-state-set! tokenizer 'comment-end-dash))
           (else (comment-append! tokenizer (nul->replacement c))))))))

  (define (state-comment-less-than-sign tokenizer)
    (cond
      ((at-end? tokenizer) (tk-state-set! tokenizer 'comment))
      (else
       (let ((c (peek tokenizer)))
         (cond
           ((char=? c #\!)
            (advance! tokenizer)
            (comment-append! tokenizer c)
            (tk-state-set! tokenizer 'comment-less-than-sign-bang))
           ((char=? c #\<)
            (advance! tokenizer)
            (comment-append! tokenizer c))
           (else (tk-state-set! tokenizer 'comment)))))))

  (define (state-comment-less-than-sign-bang tokenizer)
    (cond
      ((at-end? tokenizer) (tk-state-set! tokenizer 'comment))
      ((char=? (peek tokenizer) #\-)
       (advance! tokenizer)
       (tk-state-set! tokenizer 'comment-less-than-sign-bang-dash))
      (else (tk-state-set! tokenizer 'comment))))

  (define (state-comment-less-than-sign-bang-dash tokenizer)
    (cond
      ((at-end? tokenizer) (tk-state-set! tokenizer 'comment-end-dash))
      ((char=? (peek tokenizer) #\-)
       (advance! tokenizer)
       (tk-state-set! tokenizer 'comment-less-than-sign-bang-dash-dash))
      (else (tk-state-set! tokenizer 'comment-end-dash))))

  (define (state-comment-less-than-sign-bang-dash-dash tokenizer)
    (tk-state-set! tokenizer 'comment-end))

  (define (state-comment-end-dash tokenizer)
    (cond
      ((at-end? tokenizer)
       (comment-emit! tokenizer)
       (end-of-file-emit! tokenizer))
      ((char=? (peek tokenizer) #\-)
       (advance! tokenizer)
       (tk-state-set! tokenizer 'comment-end))
      (else
       (comment-append! tokenizer #\-)
       (tk-state-set! tokenizer 'comment))))

  (define (state-comment-end tokenizer)
    (cond
      ((at-end? tokenizer)
       (comment-emit! tokenizer)
       (end-of-file-emit! tokenizer))
      (else
       (let ((c (peek tokenizer)))
         (cond
           ((char=? c #\>)
            (advance! tokenizer)
            (comment-emit! tokenizer)
            (tk-state-set! tokenizer 'data))
           ((char=? c #\!)
            (advance! tokenizer)
            (tk-state-set! tokenizer 'comment-end-bang))
           ((char=? c #\-)
            (advance! tokenizer)
            (comment-append! tokenizer #\-))
           (else
            (comment-append-string! tokenizer "--")
            (tk-state-set! tokenizer 'comment)))))))

  (define (state-comment-end-bang tokenizer)
    (cond
      ((at-end? tokenizer)
       (comment-append-string! tokenizer "--!")
       (comment-emit! tokenizer)
       (end-of-file-emit! tokenizer))
      (else
       (let ((c (peek tokenizer)))
         (cond
           ((char=? c #\-)
            (advance! tokenizer)
            (comment-append-string! tokenizer "--!")
            (tk-state-set! tokenizer 'comment-end-dash))
           ((char=? c #\>)
            (advance! tokenizer)
            (comment-emit! tokenizer)
            (tk-state-set! tokenizer 'data))
           (else
            (comment-append-string! tokenizer "--!")
            (tk-state-set! tokenizer 'comment)))))))

  ;; 13.2.5.53-68 DOCTYPE states

  (define (doctype-emit-quirks-at-end! tokenizer)
    (tk-doctype-quirks-set! tokenizer #t)
    (doctype-emit! tokenizer)
    (end-of-file-emit! tokenizer))

  (define (state-doctype tokenizer)
    (cond
      ((at-end? tokenizer)
       (doctype-start! tokenizer)
       (doctype-emit-quirks-at-end! tokenizer))
      (else
       (let ((c (peek tokenizer)))
         (cond
           ((space-character? c)
            (advance! tokenizer)
            (doctype-start! tokenizer)
            (tk-state-set! tokenizer 'before-doctype-name))
           ((char=? c #\>)
            (doctype-start! tokenizer)
            (tk-state-set! tokenizer 'before-doctype-name))
           (else
            (doctype-start! tokenizer)
            (tk-state-set! tokenizer 'before-doctype-name)))))))

  (define (state-before-doctype-name tokenizer)
    (cond
      ((at-end? tokenizer) (doctype-emit-quirks-at-end! tokenizer))
      (else
       (let ((c (peek tokenizer)))
         (cond
           ((space-character? c) (advance! tokenizer))
           ((char=? c #\>)
            (advance! tokenizer)
            (tk-doctype-quirks-set! tokenizer #t)
            (doctype-emit! tokenizer)
            (tk-state-set! tokenizer 'data))
           (else
            (advance! tokenizer)
            (tk-doctype-name-set! tokenizer (open-output-string))
            (write-char (char-ascii-lowercase (nul->replacement c))
                        (tk-doctype-name tokenizer))
            (tk-state-set! tokenizer 'doctype-name)))))))

  (define (state-doctype-name tokenizer)
    (cond
      ((at-end? tokenizer) (doctype-emit-quirks-at-end! tokenizer))
      (else
       (let ((c (consume! tokenizer)))
         (cond
           ((space-character? c) (tk-state-set! tokenizer 'after-doctype-name))
           ((char=? c #\>)
            (doctype-emit! tokenizer)
            (tk-state-set! tokenizer 'data))
           (else
            (write-char (char-ascii-lowercase (nul->replacement c))
                        (tk-doctype-name tokenizer))))))))

  (define (state-after-doctype-name tokenizer)
    (cond
      ((at-end? tokenizer) (doctype-emit-quirks-at-end! tokenizer))
      (else
       (let ((c (peek tokenizer))
             (text (tk-text tokenizer))
             (size (tk-size tokenizer))
             (position (tk-position tokenizer)))
         (cond
           ((space-character? c) (advance! tokenizer))
           ((char=? c #\>)
            (advance! tokenizer)
            (doctype-emit! tokenizer)
            (tk-state-set! tokenizer 'data))
           ((html-scanner-ascii-startswith? text "public" position size)
            (tk-position-set! tokenizer (fx+ position 6))
            (tk-state-set! tokenizer 'after-doctype-public-keyword))
           ((html-scanner-ascii-startswith? text "system" position size)
            (tk-position-set! tokenizer (fx+ position 6))
            (tk-state-set! tokenizer 'after-doctype-system-keyword))
           (else
            (tk-doctype-quirks-set! tokenizer #t)
            (tk-state-set! tokenizer 'bogus-doctype)))))))

  (define (doctype-identifier-port-set! tokenizer which)
    (let ((port (open-output-string)))
      (if (eq? which 'public)
        (tk-doctype-public-set! tokenizer port)
        (tk-doctype-system-set! tokenizer port))
      port))

  (define (doctype-identifier-port tokenizer which)
    (if (eq? which 'public)
      (tk-doctype-public tokenizer)
      (tk-doctype-system tokenizer)))

  (define (state-after-doctype-keyword tokenizer which)
    (cond
      ((at-end? tokenizer) (doctype-emit-quirks-at-end! tokenizer))
      (else
       (let ((c (peek tokenizer)))
         (cond
           ((space-character? c)
            (advance! tokenizer)
            (tk-state-set! tokenizer (if (eq? which 'public)
                                       'before-doctype-public-identifier
                                       'before-doctype-system-identifier)))
           ((char=? c #\")
            (advance! tokenizer)
            (doctype-identifier-port-set! tokenizer which)
            (tk-state-set! tokenizer (if (eq? which 'public)
                                       'doctype-public-identifier-double-quoted
                                       'doctype-system-identifier-double-quoted)))
           ((char=? c #\')
            (advance! tokenizer)
            (doctype-identifier-port-set! tokenizer which)
            (tk-state-set! tokenizer (if (eq? which 'public)
                                       'doctype-public-identifier-single-quoted
                                       'doctype-system-identifier-single-quoted)))
           ((char=? c #\>)
            (advance! tokenizer)
            (tk-doctype-quirks-set! tokenizer #t)
            (doctype-emit! tokenizer)
            (tk-state-set! tokenizer 'data))
           (else
            (tk-doctype-quirks-set! tokenizer #t)
            (tk-state-set! tokenizer 'bogus-doctype)))))))

  (define (state-before-doctype-identifier tokenizer which)
    (cond
      ((at-end? tokenizer) (doctype-emit-quirks-at-end! tokenizer))
      (else
       (let ((c (peek tokenizer)))
         (cond
           ((space-character? c) (advance! tokenizer))
           ((char=? c #\")
            (advance! tokenizer)
            (doctype-identifier-port-set! tokenizer which)
            (tk-state-set! tokenizer (if (eq? which 'public)
                                       'doctype-public-identifier-double-quoted
                                       'doctype-system-identifier-double-quoted)))
           ((char=? c #\')
            (advance! tokenizer)
            (doctype-identifier-port-set! tokenizer which)
            (tk-state-set! tokenizer (if (eq? which 'public)
                                       'doctype-public-identifier-single-quoted
                                       'doctype-system-identifier-single-quoted)))
           ((char=? c #\>)
            (advance! tokenizer)
            (tk-doctype-quirks-set! tokenizer #t)
            (doctype-emit! tokenizer)
            (tk-state-set! tokenizer 'data))
           (else
            (tk-doctype-quirks-set! tokenizer #t)
            (tk-state-set! tokenizer 'bogus-doctype)))))))

  (define (state-doctype-identifier tokenizer which quote-character)
    (cond
      ((at-end? tokenizer) (doctype-emit-quirks-at-end! tokenizer))
      (else
       (let ((c (consume! tokenizer)))
         (cond
           ((char=? c quote-character)
            (tk-state-set! tokenizer (if (eq? which 'public)
                                       'after-doctype-public-identifier
                                       'after-doctype-system-identifier)))
           ((char=? c #\>)
            (tk-doctype-quirks-set! tokenizer #t)
            (doctype-emit! tokenizer)
            (tk-state-set! tokenizer 'data))
           (else
            (write-char (nul->replacement c)
                        (doctype-identifier-port tokenizer which))))))))

  (define (state-after-doctype-public-identifier tokenizer)
    (cond
      ((at-end? tokenizer) (doctype-emit-quirks-at-end! tokenizer))
      (else
       (let ((c (peek tokenizer)))
         (cond
           ((space-character? c)
            (advance! tokenizer)
            (tk-state-set! tokenizer 'between-doctype-public-and-system-identifiers))
           ((char=? c #\>)
            (advance! tokenizer)
            (doctype-emit! tokenizer)
            (tk-state-set! tokenizer 'data))
           ((char=? c #\")
            (advance! tokenizer)
            (doctype-identifier-port-set! tokenizer 'system)
            (tk-state-set! tokenizer 'doctype-system-identifier-double-quoted))
           ((char=? c #\')
            (advance! tokenizer)
            (doctype-identifier-port-set! tokenizer 'system)
            (tk-state-set! tokenizer 'doctype-system-identifier-single-quoted))
           (else
            (tk-doctype-quirks-set! tokenizer #t)
            (tk-state-set! tokenizer 'bogus-doctype)))))))

  (define (state-between-doctype-identifiers tokenizer)
    (cond
      ((at-end? tokenizer) (doctype-emit-quirks-at-end! tokenizer))
      (else
       (let ((c (peek tokenizer)))
         (cond
           ((space-character? c) (advance! tokenizer))
           ((char=? c #\>)
            (advance! tokenizer)
            (doctype-emit! tokenizer)
            (tk-state-set! tokenizer 'data))
           ((char=? c #\")
            (advance! tokenizer)
            (doctype-identifier-port-set! tokenizer 'system)
            (tk-state-set! tokenizer 'doctype-system-identifier-double-quoted))
           ((char=? c #\')
            (advance! tokenizer)
            (doctype-identifier-port-set! tokenizer 'system)
            (tk-state-set! tokenizer 'doctype-system-identifier-single-quoted))
           (else
            (tk-doctype-quirks-set! tokenizer #t)
            (tk-state-set! tokenizer 'bogus-doctype)))))))

  (define (state-after-doctype-system-identifier tokenizer)
    (cond
      ((at-end? tokenizer) (doctype-emit-quirks-at-end! tokenizer))
      (else
       (let ((c (peek tokenizer)))
         (cond
           ((space-character? c) (advance! tokenizer))
           ((char=? c #\>)
            (advance! tokenizer)
            (doctype-emit! tokenizer)
            (tk-state-set! tokenizer 'data))
           (else (tk-state-set! tokenizer 'bogus-doctype)))))))

  (define (state-bogus-doctype tokenizer)
    (cond
      ((at-end? tokenizer)
       (doctype-emit! tokenizer)
       (end-of-file-emit! tokenizer))
      (else
       (let ((c (consume! tokenizer)))
         (when (char=? c #\>)
           (doctype-emit! tokenizer)
           (tk-state-set! tokenizer 'data))))))

  ;; 13.2.5.69-71 CDATA section states

  (define (state-cdata-section tokenizer)
    (let* ((text (tk-text tokenizer))
           (size (tk-size tokenizer))
           (start (tk-position tokenizer))
           (close (html-scanner-ascii-find text "]]>" start size)))
      (cond
        (close
         (character-emit! tokenizer (substring text start close))
         (tk-position-set! tokenizer (fx+ close 3))
         (tk-state-set! tokenizer 'data))
        (else
         (character-emit! tokenizer (substring text start size))
         (tk-position-set! tokenizer size)
         (end-of-file-emit! tokenizer)))))

  ;; Convenience: tokenize a whole string (used by the tests).

  (define (html-tokenize text)
    (let ((tokenizer (html-tokenizer-make (html-source-preprocess text))))
      (let loop ((tokens '()))
        (let ((token (html-tokenizer-next tokenizer)))
          (cond
            ((not token) (reverse tokens))
            ((token-end-of-file? token) (reverse tokens))
            (else (loop (cons token tokens))))))))

  ;; ====================================================================
  ;; Section 5 -- tree construction, SXML, entry point
  ;; ====================================================================
  ;; Layers 4, 5 and 6 -- tree construction (WHATWG 13.2.6), SXML assembly
  ;; and the html5lib pipe-indented test format, plus the html->sxml entry
  ;; point.

  ;; ------------------------------------------------------------------
  ;; Static sets
  ;; ------------------------------------------------------------------

  (define (strings->hashtable entries)
    (let ((table (make-hashtable string-hash string=?)))
      (vector-for-each (lambda (entry) (hashtable-set! table entry #t)) entries)
      table))

  (define (pairs->hashtable entries)
    (let ((table (make-hashtable string-hash string=?)))
      (vector-for-each
        (lambda (entry) (hashtable-set! table (car entry) (cdr entry)))
        entries)
      table))

  (define (string-set-member? table name)
    (hashtable-ref table name #f))

  (define special-elements (strings->hashtable html-special-element-names))
  (define formatting-elements (strings->hashtable html-formatting-element-names))
  (define void-elements (strings->hashtable html-void-element-names))
  (define implied-end-tags (strings->hashtable html-implied-end-tag-names))
  (define foreign-breakout-elements
    (strings->hashtable html-foreign-breakout-element-names))
  (define svg-tag-name-adjustments
    (pairs->hashtable html-svg-tag-name-adjustment-entries))
  (define svg-attribute-adjustments
    (pairs->hashtable html-svg-attribute-adjustment-entries))
  (define mathml-attribute-adjustments
    (pairs->hashtable html-mathml-attribute-adjustment-entries))
  (define foreign-attribute-adjustments
    (pairs->hashtable html-foreign-attribute-adjustment-entries))

  (define (names->hashtable names)
    (strings->hashtable (list->vector names)))

  ;; Scope terminators (13.2.6.2).  The HTML-namespace names come from
  ;; justhtml's constants; the MathML and SVG ones are the spec's.
  (define default-scope-html (strings->hashtable html-default-scope-terminator-names))
  (define list-item-scope-html (names->hashtable '("ol" "ul")))
  (define button-scope-html (names->hashtable '("button")))
  (define table-scope-html (strings->hashtable html-table-scope-terminator-names))
  (define default-scope-mathml
    (names->hashtable '("mi" "mo" "mn" "ms" "mtext" "annotation-xml")))
  (define default-scope-svg (names->hashtable '("foreignObject" "desc" "title")))

  (define mathml-text-integration-names
    (names->hashtable '("mi" "mo" "mn" "ms" "mtext")))
  (define svg-html-integration-names
    (names->hashtable '("foreignObject" "desc" "title")))

  (define heading-elements (names->hashtable '("h1" "h2" "h3" "h4" "h5" "h6")))

  (define paragraph-closing-start-tags
    (names->hashtable
      '("address" "article" "aside" "blockquote" "center" "details" "dialog"
        "dir" "div" "dl" "fieldset" "figcaption" "figure" "footer" "header"
        "hgroup" "hr" "listing" "main" "menu" "nav" "ol" "p" "pre" "search"
        "section" "summary" "table" "ul" "dd" "dt" "li" "xmp"
        "h1" "h2" "h3" "h4" "h5" "h6")))

  ;; Block-level end tags handled by the "in body" generic branch.
  (define block-end-tags
    (names->hashtable
      '("address" "article" "aside" "blockquote" "button" "center" "details"
        "dialog" "dir" "div" "dl" "fieldset" "figcaption" "figure" "footer"
        "header" "hgroup" "listing" "main" "menu" "nav" "ol" "pre" "search"
        "section" "summary" "ul")))

  (define head-content-start-tags
    (names->hashtable
      '("base" "basefont" "bgsound" "link" "meta" "noframes" "script" "style"
        "template" "title")))

  (define table-context-clear-names
    (names->hashtable '("table" "template" "html")))
  (define table-body-context-clear-names
    (names->hashtable '("tbody" "tfoot" "thead" "template" "html")))
  (define table-row-context-clear-names
    (names->hashtable '("tr" "template" "html")))

  ;; ------------------------------------------------------------------
  ;; Nodes
  ;; ------------------------------------------------------------------

  (define-record-type (html-node html-node-new html-node?)
    (fields (immutable kind html-node-kind)
            (mutable name html-node-name html-node-name-set!)
            (mutable namespace html-node-namespace html-node-namespace-set!)
            (mutable attributes html-node-attributes html-node-attributes-set!)
            (mutable children html-node-children html-node-children-set!)
            (mutable parent html-node-parent html-node-parent-set!)
            (mutable data html-node-data html-node-data-set!)
            (mutable content html-node-content html-node-content-set!)))

  (define (element-node-make name namespace attributes)
    (html-node-new 'element name namespace attributes '() #f #f #f))

  (define (text-node-make text)
    (html-node-new 'text #f #f '() '() #f text #f))

  (define (comment-node-make text)
    (html-node-new 'comment #f #f '() '() #f text #f))

  (define (processing-instruction-node-make target data)
    (html-node-new 'processing-instruction target #f '() '() #f data #f))

  (define (doctype-node-make name public-id system-id)
    (html-node-new 'doctype #f #f '() '() #f (list name public-id system-id) #f))

  (define (document-node-make)
    (html-node-new 'document #f #f '() '() #f #f #f))

  (define (fragment-node-make)
    (html-node-new 'fragment #f #f '() '() #f #f #f))

  (define (node-element? node) (eq? (html-node-kind node) 'element))
  (define (node-text? node) (eq? (html-node-kind node) 'text))

  (define (node-html-element? node name)
    (and (node-element? node)
         (eq? (html-node-namespace node) 'html)
         (string=? (html-node-name node) name)))

  (define (node-detach! node)
    (let ((parent (html-node-parent node)))
      (when parent
        (html-node-children-set! parent (remq node (html-node-children parent)))
        (html-node-parent-set! node #f))))

  (define (node-append-child! parent child)
    (node-detach! child)
    (html-node-children-set! parent
                             (append (html-node-children parent) (list child)))
    (html-node-parent-set! child parent))

  (define (node-insert-before! parent child reference)
    (node-detach! child)
    (html-node-children-set!
      parent
      (let loop ((children (html-node-children parent)))
        (cond
          ((null? children) (list child))
          ((eq? (car children) reference) (cons child children))
          (else (cons (car children) (loop (cdr children)))))))
    (html-node-parent-set! child parent))

  (define (node-last-child parent)
    (let loop ((children (html-node-children parent)) (last #f))
      (if (null? children) last (loop (cdr children) (car children)))))

  (define (node-previous-sibling parent reference)
    (let loop ((children (html-node-children parent)) (previous #f))
      (cond
        ((null? children) #f)
        ((eq? (car children) reference) previous)
        (else (loop (cdr children) (car children))))))

  ;; ------------------------------------------------------------------
  ;; List helpers (the two spec "stacks" are plain lists in spec order:
  ;; the root/oldest entry first, the current node/newest entry last)
  ;; ------------------------------------------------------------------

  (define (list-index-of items item)
    (let loop ((items items) (index 0))
      (cond
        ((null? items) #f)
        ((eq? (car items) item) index)
        (else (loop (cdr items) (fx+ index 1))))))

  (define (list-remove-at items index)
    (if (fx= index 0)
      (cdr items)
      (cons (car items) (list-remove-at (cdr items) (fx- index 1)))))

  (define (list-insert-at items index item)
    (if (fx= index 0)
      (cons item items)
      (cons (car items) (list-insert-at (cdr items) (fx- index 1) item))))

  (define (list-replace-at items index item)
    (if (fx= index 0)
      (cons item (cdr items))
      (cons (car items) (list-replace-at (cdr items) (fx- index 1) item))))

  (define (list-last items)
    (let loop ((items items) (last #f))
      (if (null? items) last (loop (cdr items) (car items)))))

  ;; ------------------------------------------------------------------
  ;; Quirks mode (port of justhtml core/doctype.py)
  ;; ------------------------------------------------------------------

  (define (vector-any-prefix? prefixes text)
    (let loop ((i 0))
      (cond
        ((fx= i (vector-length prefixes)) #f)
        ((let ((prefix (vector-ref prefixes i)))
           (and (fx<= (string-length prefix) (string-length text))
                (string=? prefix (substring text 0 (string-length prefix)))))
         #t)
        (else (loop (fx+ i 1))))))

  (define (vector-any-match? matches text)
    (let loop ((i 0))
      (cond
        ((fx= i (vector-length matches)) #f)
        ((string=? (vector-ref matches i) text) #t)
        (else (loop (fx+ i 1))))))

  ;; Pure function of the DOCTYPE token; returns 'quirks, 'limited-quirks or
  ;; 'no-quirks.
  (define (html-doctype-quirks-mode name public-id system-id force-quirks?
                                    iframe-srcdoc?)
    (let ((lowered-name (and name (string-ascii-lowercase name)))
          (public-lower (and public-id (string-ascii-lowercase public-id)))
          (system-lower (and system-id (string-ascii-lowercase system-id))))
      (cond
        (force-quirks? 'quirks)
        (iframe-srcdoc? 'no-quirks)
        ((not (and lowered-name (string=? lowered-name "html"))) 'quirks)
        ((and public-lower (vector-any-match? html-quirky-public-matches public-lower))
         'quirks)
        ((and system-lower (vector-any-match? html-quirky-system-matches system-lower))
         'quirks)
        ((and public-lower (vector-any-prefix? html-quirky-public-prefixes public-lower))
         'quirks)
        ((and public-lower
              (vector-any-prefix? html-limited-quirky-public-prefixes public-lower))
         'limited-quirks)
        ((and public-lower (vector-any-prefix? html4-public-prefixes public-lower))
         (if system-lower 'limited-quirks 'quirks))
        (else 'no-quirks))))

  ;; ------------------------------------------------------------------
  ;; Parser state
  ;; ------------------------------------------------------------------

  (define-record-type (html-parser html-parser-new html-parser?)
    (fields (immutable tokenizer parser-tokenizer)
            (immutable document parser-document)
            (mutable mode parser-mode parser-mode-set!)
            (mutable original-mode parser-original-mode parser-original-mode-set!)
            (mutable stack parser-stack parser-stack-set!)
            (mutable formatting parser-formatting parser-formatting-set!)
            (mutable head parser-head parser-head-set!)
            (mutable form parser-form parser-form-set!)
            (mutable frameset-ok? parser-frameset-ok? parser-frameset-ok-set!)
            (mutable scripting? parser-scripting? parser-scripting-set!)
            (mutable iframe-srcdoc? parser-iframe-srcdoc? parser-iframe-srcdoc-set!)
            (mutable quirks parser-quirks parser-quirks-set!)
            (mutable template-modes parser-template-modes parser-template-modes-set!)
            (mutable foster? parser-foster? parser-foster-set!)
            (mutable table-text parser-table-text parser-table-text-set!)
            (mutable fragment-context parser-fragment-context
                     parser-fragment-context-set!)
            (mutable root parser-root parser-root-set!)
            (mutable skip-newline? parser-skip-newline? parser-skip-newline-set!)
            (mutable done? parser-done? parser-done-set!)
            (mutable coerce? parser-coerce? parser-coerce-set!)))

  (define (parser-make text scripting? iframe-srcdoc? coerce?)
    (let ((tokenizer (html-tokenizer-make text)))
      (html-tokenizer-scripting-set! tokenizer scripting?)
      (html-parser-new tokenizer (document-node-make) 'initial 'initial
                       '() '() #f #f #t scripting? iframe-srcdoc?
                       'no-quirks '() #f '() #f #f #f #f coerce?)))

  (define (parser-current parser)
    (list-last (parser-stack parser)))

  (define (parser-fragment? parser)
    (and (parser-fragment-context parser) #t))

  (define (parser-adjusted-current parser)
    (let ((stack (parser-stack parser)))
      (cond
        ((null? stack) #f)
        ((and (parser-fragment? parser) (fx= (length stack) 1))
         (parser-fragment-context parser))
        (else (list-last stack)))))

  (define (stack-push! parser node)
    (parser-stack-set! parser (append (parser-stack parser) (list node))))

  (define (stack-pop! parser)
    (let* ((stack (parser-stack parser))
           (size (length stack)))
      (parser-stack-set! parser (list-remove-at stack (fx- size 1)))))

  (define (stack-remove! parser node)
    (parser-stack-set! parser (remq node (parser-stack parser))))

  (define (stack-contains? parser node)
    (and (memq node (parser-stack parser)) #t))

  (define (stack-pop-until-name! parser name)
    (let loop ()
      (let ((current (parser-current parser)))
        (cond
          ((not current) #f)
          ((node-html-element? current name) (stack-pop! parser))
          (else (stack-pop! parser) (loop))))))

  (define (stack-pop-until-node! parser node)
    (let loop ()
      (let ((current (parser-current parser)))
        (cond
          ((not current) #f)
          ((eq? current node) (stack-pop! parser))
          (else (stack-pop! parser) (loop))))))

  (define (stack-find-name parser name)
    (let loop ((items (reverse (parser-stack parser))))
      (cond
        ((null? items) #f)
        ((node-html-element? (car items) name) (car items))
        (else (loop (cdr items))))))

  ;; ------------------------------------------------------------------
  ;; Scope algorithms
  ;; ------------------------------------------------------------------

  (define (scope-terminator? node extra-html)
    (let ((namespace (html-node-namespace node))
          (name (html-node-name node)))
      (case namespace
        ((html) (or (string-set-member? default-scope-html name)
                    (and extra-html (string-set-member? extra-html name))))
        ((math) (string-set-member? default-scope-mathml name))
        ((svg) (string-set-member? default-scope-svg name))
        (else #f))))

  (define (element-in-scope? parser names extra-html)
    (let loop ((items (reverse (parser-stack parser))))
      (cond
        ((null? items) #f)
        ((and (eq? (html-node-namespace (car items)) 'html)
              (member (html-node-name (car items)) names))
         #t)
        ((scope-terminator? (car items) extra-html) #f)
        (else (loop (cdr items))))))

  (define (element-in-default-scope? parser name)
    (element-in-scope? parser (list name) #f))

  (define (element-in-button-scope? parser name)
    (element-in-scope? parser (list name) button-scope-html))

  (define (element-in-list-item-scope? parser name)
    (element-in-scope? parser (list name) list-item-scope-html))

  (define (element-in-table-scope? parser names)
    (let loop ((items (reverse (parser-stack parser))))
      (cond
        ((null? items) #f)
        ((and (eq? (html-node-namespace (car items)) 'html)
              (member (html-node-name (car items)) names))
         #t)
        ((and (eq? (html-node-namespace (car items)) 'html)
              (string-set-member? table-scope-html (html-node-name (car items))))
         #f)
        (else (loop (cdr items))))))

  (define (element-in-select-scope? parser name)
    (let loop ((items (reverse (parser-stack parser))))
      (cond
        ((null? items) #f)
        ((node-html-element? (car items) name) #t)
        ((or (node-html-element? (car items) "option")
             (node-html-element? (car items) "optgroup"))
         (loop (cdr items)))
        (else #f))))

  ;; ------------------------------------------------------------------
  ;; Active formatting elements
  ;; ------------------------------------------------------------------

  (define (formatting-marker? entry) (eq? entry 'marker))

  (define (formatting-marker-insert! parser)
    (parser-formatting-set! parser (append (parser-formatting parser) '(marker))))

  (define (formatting-clear-to-marker! parser)
    (let loop ((items (reverse (parser-formatting parser))))
      (cond
        ((null? items) (parser-formatting-set! parser '()))
        ((formatting-marker? (car items))
         (parser-formatting-set! parser (reverse (cdr items))))
        (else (loop (cdr items))))))

  (define (attributes-equal? a b)
    (and (fx= (length a) (length b))
         (let loop ((a a))
           (or (null? a)
               (let ((pair (assoc (car (car a)) b)))
                 (and pair
                      (string=? (cdr pair) (cdr (car a)))
                      (loop (cdr a))))))))

  ;; Push onto the list of active formatting elements, applying the Noah's
  ;; Ark clause: at most three entries with the same name, namespace and
  ;; attributes may follow the last marker.
  (define (formatting-push! parser node)
    (let* ((items (parser-formatting parser))
           (after-marker
            (let loop ((items (reverse items)) (result '()))
              (cond
                ((null? items) result)
                ((formatting-marker? (car items)) result)
                (else (loop (cdr items) (cons (car items) result))))))
           (matches
            (let loop ((items after-marker) (result '()))
              (cond
                ((null? items) (reverse result))
                ((and (string=? (html-node-name (car items)) (html-node-name node))
                      (eq? (html-node-namespace (car items))
                           (html-node-namespace node))
                      (attributes-equal? (html-node-attributes (car items))
                                         (html-node-attributes node)))
                 (loop (cdr items) (cons (car items) result)))
                (else (loop (cdr items) result))))))
      (when (fx>= (length matches) 3)
        (parser-formatting-set! parser (remq (car matches) (parser-formatting parser))))
      (parser-formatting-set! parser
                              (append (parser-formatting parser) (list node)))))

  (define (formatting-find-after-marker parser name)
    (let loop ((items (reverse (parser-formatting parser))))
      (cond
        ((null? items) #f)
        ((formatting-marker? (car items)) #f)
        ((string=? (html-node-name (car items)) name) (car items))
        (else (loop (cdr items))))))

  (define (formatting-reconstruct! parser)
    (let ((items (parser-formatting parser)))
      (unless (null? items)
        (let ((last-entry (list-last items)))
          (unless (or (formatting-marker? last-entry)
                      (stack-contains? parser last-entry))
            ;; Rewind to the first entry that must be recreated.
            (let* ((size (length items))
                   (start
                    (let loop ((index (fx- size 1)))
                      (let ((entry (list-ref items index)))
                        (cond
                          ((fx= index 0) 0)
                          ((or (formatting-marker? entry)
                               (stack-contains? parser entry))
                           (fx+ index 1))
                          (else (loop (fx- index 1))))))))
              (let loop ((index start))
                (when (fx< index (length (parser-formatting parser)))
                  (let* ((entry (list-ref (parser-formatting parser) index))
                         (node (element-node-make (html-node-name entry)
                                                  (html-node-namespace entry)
                                                  (html-node-attributes entry))))
                    (node-insert! parser node)
                    (stack-push! parser node)
                    (parser-formatting-set!
                      parser
                      (list-replace-at (parser-formatting parser) index node))
                    (loop (fx+ index 1)))))))))))

  ;; ------------------------------------------------------------------
  ;; Insertion locations
  ;; ------------------------------------------------------------------

  ;; Returns (values parent reference) where reference is #false to append.
  (define (insertion-location parser override-target)
    (let ((target (or override-target (parser-current parser))))
      (cond
        ((and (parser-foster? parser)
              target
              (node-element? target)
              (eq? (html-node-namespace target) 'html)
              (member (html-node-name target) '("table" "tbody" "tfoot" "thead" "tr")))
         (foster-parent-location parser))
        ((and target (node-html-element? target "template") (html-node-content target))
         (values (html-node-content target) #f))
        (else (values target #f)))))

  (define (foster-parent-location parser)
    (let* ((stack (parser-stack parser))
           (reversed (reverse stack))
           (last-template
            (let loop ((items reversed))
              (cond
                ((null? items) #f)
                ((node-html-element? (car items) "template") (car items))
                (else (loop (cdr items))))))
           (last-table
            (let loop ((items reversed))
              (cond
                ((null? items) #f)
                ((node-html-element? (car items) "table") (car items))
                (else (loop (cdr items)))))))
      (cond
        ((and last-template
              (or (not last-table)
                  (fx> (list-index-of stack last-template)
                       (list-index-of stack last-table))))
         (values (html-node-content last-template) #f))
        ((not last-table) (values (car stack) #f))
        ((html-node-parent last-table)
         (values (html-node-parent last-table) last-table))
        (else
         (let ((index (list-index-of stack last-table)))
           (values (list-ref stack (fx- index 1)) #f))))))

  (define (node-insert! parser node)
    (call-with-values
      (lambda () (insertion-location parser #f))
      (lambda (parent reference)
        (when parent
          (if reference
            (node-insert-before! parent node reference)
            (node-append-child! parent node))))))

  (define (node-insert-at! parser node override-target)
    (call-with-values
      (lambda () (insertion-location parser override-target))
      (lambda (parent reference)
        (when parent
          (if reference
            (node-insert-before! parent node reference)
            (node-append-child! parent node))))))

  ;; XML coercion (justhtml's _coerce_text_for_xml): form feed becomes a
  ;; space and the XML-invalid noncharacters become U+FFFD.  Off by default;
  ;; the xml-coercion fixtures switch it on.
  (define (text-coerce-for-xml text)
    (list->string
      (map (lambda (c)
             (let ((code (char->integer c)))
               (cond
                 ((char=? c #\page) #\space)
                 ((and (fx>= code #xFDD0) (fx<= code #xFDEF)) (integer->char #xFFFD))
                 ((let ((low (fxand code #xFFFF)))
                    (or (fx= low #xFFFE) (fx= low #xFFFF)))
                  (integer->char #xFFFD))
                 (else c))))
           (string->list text))))

  (define (characters-insert! parser raw)
    (let ((text (if (parser-coerce? parser) (text-coerce-for-xml raw) raw)))
      (characters-insert-plain! parser text)))

  (define (characters-insert-plain! parser text)
    (unless (fx= (string-length text) 0)
      (call-with-values
        (lambda () (insertion-location parser #f))
        (lambda (parent reference)
          (when parent
            (let ((previous (if reference
                              (node-previous-sibling parent reference)
                              (node-last-child parent))))
              (if (and previous (node-text? previous))
                ;; Adjacent text nodes are merged.
                (html-node-data-set! previous
                                     (string-append (html-node-data previous) text))
                (let ((node (text-node-make text)))
                  (if reference
                    (node-insert-before! parent node reference)
                    (node-append-child! parent node))))))))))

  ;; ------------------------------------------------------------------
  ;; Element creation
  ;; ------------------------------------------------------------------

  (define (element-insert! parser name namespace attributes)
    (let ((node (element-node-make name namespace attributes)))
      (node-insert! parser node)
      (stack-push! parser node)
      node))

  (define (element-insert-token! parser token)
    (element-insert! parser (token-start-tag-name token) 'html
                     (token-start-tag-attributes token)))

  ;; ------------------------------------------------------------------
  ;; Implied end tags
  ;; ------------------------------------------------------------------

  (define (implied-end-tags-generate! parser except)
    (let loop ()
      (let ((current (parser-current parser)))
        (when (and current
                   (node-element? current)
                   (eq? (html-node-namespace current) 'html)
                   (string-set-member? implied-end-tags (html-node-name current))
                   (not (and except (string=? (html-node-name current) except))))
          (stack-pop! parser)
          (loop)))))

  (define (implied-end-tags-generate-thoroughly! parser)
    (let loop ()
      (let ((current (parser-current parser)))
        (when (and current
                   (node-element? current)
                   (eq? (html-node-namespace current) 'html)
                   (or (string-set-member? implied-end-tags (html-node-name current))
                       (member (html-node-name current)
                               '("caption" "colgroup" "tbody" "td" "tfoot" "th"
                                 "thead" "tr"))))
          (stack-pop! parser)
          (loop)))))

  (define (paragraph-close! parser)
    (implied-end-tags-generate! parser "p")
    (stack-pop-until-name! parser "p"))

  ;; ------------------------------------------------------------------
  ;; Reset the insertion mode appropriately (13.2.6.1)
  ;; ------------------------------------------------------------------

  (define (insertion-mode-reset! parser)
    (let* ((stack (parser-stack parser))
           (size (length stack)))
      (let loop ((index (fx- size 1)))
        (let* ((last? (fx= index 0))
               (node (if (and last? (parser-fragment? parser))
                       (parser-fragment-context parser)
                       (list-ref stack index)))
               (name (and (node-element? node) (html-node-name node)))
               (html? (and (node-element? node)
                           (eq? (html-node-namespace node) 'html))))
          (cond
            ((and html? (string=? name "select"))
             (parser-mode-set! parser (select-insertion-mode parser index)))
            ((and html? (or (string=? name "td") (string=? name "th")) (not last?))
             (parser-mode-set! parser 'in-cell))
            ((and html? (string=? name "tr")) (parser-mode-set! parser 'in-row))
            ((and html? (member name '("tbody" "thead" "tfoot")))
             (parser-mode-set! parser 'in-table-body))
            ((and html? (string=? name "caption")) (parser-mode-set! parser 'in-caption))
            ((and html? (string=? name "colgroup"))
             (parser-mode-set! parser 'in-column-group))
            ((and html? (string=? name "table")) (parser-mode-set! parser 'in-table))
            ((and html? (string=? name "template"))
             (parser-mode-set! parser (or (list-last (parser-template-modes parser))
                                          'in-body)))
            ((and html? (string=? name "head") (not last?))
             (parser-mode-set! parser 'in-head))
            ((and html? (string=? name "body")) (parser-mode-set! parser 'in-body))
            ((and html? (string=? name "frameset"))
             (parser-mode-set! parser 'in-frameset))
            ((and html? (string=? name "html"))
             (parser-mode-set! parser (if (parser-head parser) 'after-head 'before-head)))
            (last? (parser-mode-set! parser 'in-body))
            (else (loop (fx- index 1))))))))

  (define (select-insertion-mode parser index)
    (let ((stack (parser-stack parser)))
      (let loop ((i (fx- index 1)))
        (cond
          ((fx< i 0) 'in-select)
          ((node-html-element? (list-ref stack i) "template") 'in-select)
          ((node-html-element? (list-ref stack i) "table") 'in-select-in-table)
          (else (loop (fx- i 1)))))))

  ;; ------------------------------------------------------------------
  ;; Foreign content helpers
  ;; ------------------------------------------------------------------

  (define (mathml-text-integration-point? node)
    (and node
         (node-element? node)
         (eq? (html-node-namespace node) 'math)
         (string-set-member? mathml-text-integration-names (html-node-name node))))

  (define (html-integration-point? node)
    (and node
         (node-element? node)
         (case (html-node-namespace node)
           ((svg) (string-set-member? svg-html-integration-names (html-node-name node)))
           ((math)
            (and (string=? (html-node-name node) "annotation-xml")
                 (let ((encoding (assoc "encoding" (html-node-attributes node))))
                   (and encoding
                        (let ((value (string-ascii-lowercase (cdr encoding))))
                          (or (string=? value "text/html")
                              (string=? value "application/xhtml+xml")))))))
           (else #f))))

  (define (attributes-adjust-mathml attributes)
    (map (lambda (pair)
           (let ((replacement (hashtable-ref mathml-attribute-adjustments
                                             (car pair) #f)))
             (if replacement (cons replacement (cdr pair)) pair)))
         attributes))

  (define (attributes-adjust-svg attributes)
    (map (lambda (pair)
           (let ((replacement (hashtable-ref svg-attribute-adjustments
                                             (car pair) #f)))
             (if replacement (cons replacement (cdr pair)) pair)))
         attributes))

  (define (attributes-adjust-foreign attributes)
    (map (lambda (pair)
           (let ((replacement (hashtable-ref foreign-attribute-adjustments
                                             (string-ascii-lowercase (car pair)) #f)))
             (if replacement (cons replacement (cdr pair)) pair)))
         attributes))

  (define (svg-tag-name-adjust name)
    (or (hashtable-ref svg-tag-name-adjustments name #f) name))

  ;; ------------------------------------------------------------------
  ;; The main loop
  ;; ------------------------------------------------------------------

  (define (parser-run! parser)
    (let loop ()
      (unless (parser-done? parser)
        (let ((adjusted (parser-adjusted-current parser)))
          (html-tokenizer-foreign-set!
            (parser-tokenizer parser)
            (and adjusted
                 (node-element? adjusted)
                 (not (eq? (html-node-namespace adjusted) 'html)))))
        (let ((token (html-tokenizer-next (parser-tokenizer parser))))
          (cond
            ((not token) (parser-done-set! parser #t))
            (else
             ;; The tokenizer guesses a content model from the tag name; tree
             ;; construction is what really decides, so undo the guess and let
             ;; the insertion modes set the state they need.
             (when (token-start-tag? token)
               (html-tokenizer-state-set! (parser-tokenizer parser) 'data))
             (token-dispatch parser token)
             (loop)))))))

  (define (token-dispatch parser token)
    (let* ((adjusted (parser-adjusted-current parser))
           (html-rules?
            (or (not adjusted)
                (not (node-element? adjusted))
                (eq? (html-node-namespace adjusted) 'html)
                (token-end-of-file? token)
                (and (mathml-text-integration-point? adjusted)
                     (or (token-character? token)
                         (and (token-start-tag? token)
                              (not (member (token-start-tag-name token)
                                           '("mglyph" "malignmark"))))))
                (and (node-element? adjusted)
                     (eq? (html-node-namespace adjusted) 'math)
                     (string=? (html-node-name adjusted) "annotation-xml")
                     (token-start-tag? token)
                     (string=? (token-start-tag-name token) "svg"))
                (and (html-integration-point? adjusted)
                     (or (token-character? token) (token-start-tag? token))))))
      (if html-rules?
        (mode-process parser (parser-mode parser) token)
        (foreign-content-process parser token))))

  (define (token-reprocess parser token)
    (token-dispatch parser token))

  ;; Character tokens arrive as runs; these helpers split them the way the
  ;; spec's per-character rules require.

  (define (string-nul-drop text)
    (let ((port (open-output-string)))
      (let loop ((i 0))
        (cond
          ((fx>= i (string-length text)) (get-output-string port))
          (else
           (let ((c (string-ref text i)))
             (unless (char=? c #\nul) (write-char c port))
             (loop (fx+ i 1))))))))

  (define (string-all-space? text)
    (let loop ((i 0))
      (or (fx>= i (string-length text))
          (and (html-space-character? (string-ref text i))
               (loop (fx+ i 1))))))

  (define (string-leading-space-split text)
    ;; Returns (values leading-whitespace remainder).
    (let loop ((i 0))
      (cond
        ((fx>= i (string-length text)) (values text ""))
        ((html-space-character? (string-ref text i)) (loop (fx+ i 1)))
        (else (values (substring text 0 i)
                      (substring text i (string-length text)))))))

  (define (newline-skip parser text)
    (cond
      ((parser-skip-newline? parser)
       (parser-skip-newline-set! parser #f)
       (if (and (fx> (string-length text) 0)
                (char=? (string-ref text 0) #\newline))
         (substring text 1 (string-length text))
         text))
      (else text)))

  ;; ------------------------------------------------------------------
  ;; Insertion mode dispatch
  ;; ------------------------------------------------------------------

  (define (mode-process parser mode token)
    ;; U+0000 never survives HTML tree construction; dropping it here keeps
    ;; the per-mode rules from having to special-case it, and matches the way
    ;; leading whitespace is then ignored by "initial" and friends.
    (if (and (token-character? token)
             (string-nul-present? (token-character-text token)))
      (let ((text (string-nul-drop (token-character-text token))))
        (unless (string=? text "")
          (mode-process-dispatch parser mode (token-character-make text))))
      (mode-process-dispatch parser mode token)))

  (define (string-nul-present? text)
    (let loop ((i 0))
      (cond
        ((fx>= i (string-length text)) #f)
        ((char=? (string-ref text i) #\nul) #t)
        (else (loop (fx+ i 1))))))

  (define (mode-process-dispatch parser mode token)
    (case mode
      ((initial) (mode-initial parser token))
      ((before-html) (mode-before-html parser token))
      ((before-head) (mode-before-head parser token))
      ((in-head) (mode-in-head parser token))
      ((in-head-noscript) (mode-in-head-noscript parser token))
      ((after-head) (mode-after-head parser token))
      ((in-body) (mode-in-body parser token))
      ((text) (mode-text parser token))
      ((in-table) (mode-in-table parser token))
      ((in-table-text) (mode-in-table-text parser token))
      ((in-caption) (mode-in-caption parser token))
      ((in-column-group) (mode-in-column-group parser token))
      ((in-table-body) (mode-in-table-body parser token))
      ((in-row) (mode-in-row parser token))
      ((in-cell) (mode-in-cell parser token))
      ((in-select) (mode-in-select parser token))
      ((in-select-in-table) (mode-in-select-in-table parser token))
      ((in-template) (mode-in-template parser token))
      ((after-body) (mode-after-body parser token))
      ((in-frameset) (mode-in-frameset parser token))
      ((after-frameset) (mode-after-frameset parser token))
      ((after-after-body) (mode-after-after-body parser token))
      ((after-after-frameset) (mode-after-after-frameset parser token))
      (else (error 'mode-process "unknown insertion mode" mode))))

  ;; Comments and processing instructions travel the same paths through the
  ;; insertion modes.
  (define (token-comment-like? token)
    (or (token-comment? token) (token-processing-instruction? token)))

  (define (comment-like-node-make token)
    (if (token-processing-instruction? token)
      (processing-instruction-node-make
        (token-processing-instruction-target token)
        (token-processing-instruction-data token))
      (comment-node-make (token-comment-text token))))

  (define (comment-insert! parser token)
    (node-insert! parser (comment-like-node-make token)))

  (define (comment-append-to! parser token target)
    (node-append-child! target (comment-like-node-make token)))

  ;; 13.2.6.4.1 "initial"

  (define (mode-initial parser token)
    (cond
      ((token-character? token)
       (call-with-values
         (lambda () (string-leading-space-split (token-character-text token)))
         (lambda (space rest)
           (unless (string=? rest "")
             (unless (parser-iframe-srcdoc? parser)
               (parser-quirks-set! parser 'quirks))
             (parser-mode-set! parser 'before-html)
             (token-reprocess parser (token-character-make rest))))))
      ((token-comment-like? token)
       (comment-append-to! parser token (parser-document parser)))
      ((token-doctype? token)
       (let ((name (token-doctype-name token))
             (public-id (token-doctype-public-id token))
             (system-id (token-doctype-system-id token)))
         (node-append-child! (parser-document parser)
                             (doctype-node-make name public-id system-id))
         (parser-quirks-set!
           parser
           (html-doctype-quirks-mode name public-id system-id
                                     (token-doctype-force-quirks? token)
                                     (parser-iframe-srcdoc? parser)))
         (parser-mode-set! parser 'before-html)))
      ((token-end-of-file? token)
       (unless (parser-iframe-srcdoc? parser)
         (parser-quirks-set! parser 'quirks))
       (parser-mode-set! parser 'before-html)
       (token-reprocess parser token))
      (else
       (unless (parser-iframe-srcdoc? parser)
         (parser-quirks-set! parser 'quirks))
       (parser-mode-set! parser 'before-html)
       (token-reprocess parser token))))

  ;; 13.2.6.4.2 "before html"

  (define (before-html-default parser token)
    (let ((node (element-node-make "html" 'html '())))
      (node-append-child! (parser-document parser) node)
      (stack-push! parser node)
      (parser-root-set! parser node)
      (parser-mode-set! parser 'before-head)
      (token-reprocess parser token)))

  (define (mode-before-html parser token)
    (cond
      ((token-doctype? token) #f)
      ((token-comment-like? token)
       (comment-append-to! parser token (parser-document parser)))
      ((token-character? token)
       (call-with-values
         (lambda () (string-leading-space-split (token-character-text token)))
         (lambda (space rest)
           (unless (string=? rest "")
             (before-html-default parser (token-character-make rest))))))
      ((and (token-start-tag? token) (string=? (token-start-tag-name token) "html"))
       (let ((node (element-node-make "html" 'html
                                      (token-start-tag-attributes token))))
         (node-append-child! (parser-document parser) node)
         (stack-push! parser node)
         (parser-root-set! parser node)
         (parser-mode-set! parser 'before-head)))
      ((and (token-end-tag? token)
            (not (member (token-end-tag-name token) '("head" "body" "html" "br"))))
       #f)
      (else (before-html-default parser token))))

  ;; 13.2.6.4.3 "before head"

  (define (mode-before-head parser token)
    (cond
      ((token-character? token)
       (call-with-values
         (lambda () (string-leading-space-split (token-character-text token)))
         (lambda (space rest)
           (unless (string=? rest "")
             (before-head-default parser (token-character-make rest))))))
      ((token-comment-like? token) (comment-insert! parser token))
      ((token-doctype? token) #f)
      ((and (token-start-tag? token) (string=? (token-start-tag-name token) "html"))
       (mode-in-body parser token))
      ((and (token-start-tag? token) (string=? (token-start-tag-name token) "head"))
       (let ((node (element-insert-token! parser token)))
         (parser-head-set! parser node)
         (parser-mode-set! parser 'in-head)))
      ((and (token-end-tag? token)
            (not (member (token-end-tag-name token) '("head" "body" "html" "br"))))
       #f)
      (else (before-head-default parser token))))

  (define (before-head-default parser token)
    (let ((node (element-insert! parser "head" 'html '())))
      (parser-head-set! parser node)
      (parser-mode-set! parser 'in-head)
      (token-reprocess parser token)))

  ;; 13.2.6.4.4 "in head"

  (define (generic-rawtext-parse! parser token state)
    (element-insert-token! parser token)
    (html-tokenizer-last-start-tag-set! (parser-tokenizer parser)
                                        (token-start-tag-name token))
    (html-tokenizer-state-set! (parser-tokenizer parser) state)
    (parser-original-mode-set! parser (parser-mode parser))
    (parser-mode-set! parser 'text))

  (define (void-element-insert! parser token)
    (element-insert-token! parser token)
    (stack-pop! parser))

  (define (mode-in-head parser token)
    (cond
      ((token-character? token)
       (call-with-values
         (lambda () (string-leading-space-split (token-character-text token)))
         (lambda (space rest)
           (characters-insert! parser space)
           (unless (string=? rest "")
             (in-head-default parser (token-character-make rest))))))
      ((token-comment-like? token) (comment-insert! parser token))
      ((token-doctype? token) #f)
      ((token-start-tag? token)
       (let ((name (token-start-tag-name token)))
         (cond
           ((string=? name "html") (mode-in-body parser token))
           ((member name '("base" "basefont" "bgsound" "link" "meta"))
            (void-element-insert! parser token))
           ((string=? name "title") (generic-rawtext-parse! parser token 'rcdata))
           ((and (string=? name "noscript") (parser-scripting? parser))
            (generic-rawtext-parse! parser token 'rawtext))
           ((member name '("noframes" "style"))
            (generic-rawtext-parse! parser token 'rawtext))
           ((string=? name "noscript")
            (element-insert-token! parser token)
            (parser-mode-set! parser 'in-head-noscript))
           ((string=? name "script")
            (generic-rawtext-parse! parser token 'script-data))
           ((string=? name "template")
            (let ((node (element-insert-token! parser token)))
              (html-node-content-set! node (fragment-node-make))
              (formatting-marker-insert! parser)
              (parser-frameset-ok-set! parser #f)
              (parser-mode-set! parser 'in-template)
              (parser-template-modes-set!
                parser (append (parser-template-modes parser) '(in-template)))))
           ((string=? name "head") #f)
           (else (in-head-default parser token)))))
      ((token-end-tag? token)
       (let ((name (token-end-tag-name token)))
         (cond
           ((string=? name "head")
            (stack-pop! parser)
            (parser-mode-set! parser 'after-head))
           ((string=? name "template") (template-end! parser))
           ((member name '("body" "html" "br")) (in-head-default parser token))
           (else #f))))
      (else (in-head-default parser token))))

  (define (in-head-default parser token)
    (stack-pop! parser)
    (parser-mode-set! parser 'after-head)
    (token-reprocess parser token))

  (define (template-end! parser)
    (cond
      ((not (stack-find-name parser "template")) #f)
      (else
       (implied-end-tags-generate-thoroughly! parser)
       (stack-pop-until-name! parser "template")
       (formatting-clear-to-marker! parser)
       (let ((modes (parser-template-modes parser)))
         (unless (null? modes)
           (parser-template-modes-set! parser
                                       (list-remove-at modes (fx- (length modes) 1)))))
       (insertion-mode-reset! parser))))

  ;; 13.2.6.4.5 "in head noscript"

  (define (mode-in-head-noscript parser token)
    (cond
      ((token-doctype? token) #f)
      ((and (token-start-tag? token) (string=? (token-start-tag-name token) "html"))
       (mode-in-body parser token))
      ((and (token-end-tag? token) (string=? (token-end-tag-name token) "noscript"))
       (stack-pop! parser)
       (parser-mode-set! parser 'in-head))
      ((token-character? token)
       (call-with-values
         (lambda () (string-leading-space-split (token-character-text token)))
         (lambda (space rest)
           (characters-insert! parser space)
           (unless (string=? rest "")
             (in-head-noscript-default parser (token-character-make rest))))))
      ((token-comment-like? token) (mode-in-head parser token))
      ((and (token-start-tag? token)
            (member (token-start-tag-name token)
                    '("basefont" "bgsound" "link" "meta" "noframes" "style")))
       (mode-in-head parser token))
      ((and (token-start-tag? token)
            (member (token-start-tag-name token) '("head" "noscript")))
       #f)
      ((and (token-end-tag? token) (not (string=? (token-end-tag-name token) "br")))
       #f)
      (else (in-head-noscript-default parser token))))

  (define (in-head-noscript-default parser token)
    (stack-pop! parser)
    (parser-mode-set! parser 'in-head)
    (token-reprocess parser token))

  ;; 13.2.6.4.6 "after head"

  (define (mode-after-head parser token)
    (cond
      ((token-character? token)
       (call-with-values
         (lambda () (string-leading-space-split (token-character-text token)))
         (lambda (space rest)
           (characters-insert! parser space)
           (unless (string=? rest "")
             (after-head-default parser (token-character-make rest))))))
      ((token-comment-like? token) (comment-insert! parser token))
      ((token-doctype? token) #f)
      ((token-start-tag? token)
       (let ((name (token-start-tag-name token)))
         (cond
           ((string=? name "html") (mode-in-body parser token))
           ((string=? name "body")
            (element-insert-token! parser token)
            (parser-frameset-ok-set! parser #f)
            (parser-mode-set! parser 'in-body))
           ((string=? name "frameset")
            (element-insert-token! parser token)
            (parser-mode-set! parser 'in-frameset))
           ((string-set-member? head-content-start-tags name)
            (let ((head (parser-head parser)))
              (stack-push! parser head)
              (mode-in-head parser token)
              (stack-remove! parser head)))
           ((string=? name "head") #f)
           (else (after-head-default parser token)))))
      ((token-end-tag? token)
       (let ((name (token-end-tag-name token)))
         (cond
           ((string=? name "template") (mode-in-head parser token))
           ((member name '("body" "html" "br")) (after-head-default parser token))
           (else #f))))
      (else (after-head-default parser token))))

  (define (after-head-default parser token)
    (element-insert! parser "body" 'html '())
    (parser-mode-set! parser 'in-body)
    (token-reprocess parser token))

  ;; 13.2.6.4.7 "in body"

  (define (attributes-merge! node attributes)
    (for-each
      (lambda (pair)
        (unless (assoc (car pair) (html-node-attributes node))
          (html-node-attributes-set! node
                                     (append (html-node-attributes node)
                                             (list pair)))))
      attributes))

  (define (mode-in-body parser token)
    (cond
      ((token-character? token)
       (let ((text (string-nul-drop (newline-skip parser (token-character-text token)))))
         (unless (string=? text "")
           (formatting-reconstruct! parser)
           (characters-insert! parser text)
           (unless (string-all-space? text)
             (parser-frameset-ok-set! parser #f)))))
      ((token-comment-like? token) (comment-insert! parser token))
      ((token-doctype? token) #f)
      ((token-start-tag? token) (in-body-start-tag parser token))
      ((token-end-tag? token) (in-body-end-tag parser token))
      ((token-end-of-file? token)
       (if (null? (parser-template-modes parser))
         (parser-done-set! parser #t)
         (mode-in-template parser token)))
      (else #f)))

  (define (in-body-start-tag parser token)
    (let ((name (token-start-tag-name token))
          (attributes (token-start-tag-attributes token)))
      (cond
        ((string=? name "html")
         (unless (stack-find-name parser "template")
           (attributes-merge! (car (parser-stack parser)) attributes)))
        ((string-set-member? head-content-start-tags name)
         (mode-in-head parser token))
        ((string=? name "body")
         (let ((stack (parser-stack parser)))
           (when (and (fx> (length stack) 1)
                      (node-html-element? (list-ref stack 1) "body")
                      (not (stack-find-name parser "template")))
             (parser-frameset-ok-set! parser #f)
             (attributes-merge! (list-ref stack 1) attributes))))
        ((string=? name "frameset")
         (let ((stack (parser-stack parser)))
           (when (and (fx> (length stack) 1)
                      (node-html-element? (list-ref stack 1) "body")
                      (parser-frameset-ok? parser)
                      (frameset-body-allowed? (list-ref stack 1)))
             (let ((body (list-ref stack 1)))
               (node-detach! body))
             (let loop ()
               (when (fx> (length (parser-stack parser)) 1)
                 (stack-pop! parser)
                 (loop)))
             (element-insert-token! parser token)
             (parser-mode-set! parser 'in-frameset))))
        ((member name '("li" "dd" "dt")) (in-body-list-item-start parser token name))
        ((string-set-member? heading-elements name)
         (when (element-in-button-scope? parser "p") (paragraph-close! parser))
         (let ((current (parser-current parser)))
           (when (and current
                      (node-element? current)
                      (eq? (html-node-namespace current) 'html)
                      (string-set-member? heading-elements (html-node-name current)))
             (stack-pop! parser)))
         (element-insert-token! parser token))
        ((member name '("pre" "listing"))
         (when (element-in-button-scope? parser "p") (paragraph-close! parser))
         (element-insert-token! parser token)
         (parser-skip-newline-set! parser #t)
         (parser-frameset-ok-set! parser #f))
        ((string=? name "form")
         (unless (and (parser-form parser) (not (stack-find-name parser "template")))
           (when (element-in-button-scope? parser "p") (paragraph-close! parser))
           (let ((node (element-insert-token! parser token)))
             (unless (stack-find-name parser "template")
               (parser-form-set! parser node)))))
        ((string=? name "plaintext")
         (when (element-in-button-scope? parser "p") (paragraph-close! parser))
         (element-insert-token! parser token)
         (html-tokenizer-state-set! (parser-tokenizer parser) 'plaintext))
        ((string=? name "button")
         (when (element-in-default-scope? parser "button")
           (implied-end-tags-generate! parser #f)
           (stack-pop-until-name! parser "button"))
         (formatting-reconstruct! parser)
         (element-insert-token! parser token)
         (parser-frameset-ok-set! parser #f))
        ((string=? name "a")
         (let ((existing (formatting-find-after-marker parser "a")))
           (when existing
             (adoption-agency parser "a")
             (parser-formatting-set! parser (remq existing (parser-formatting parser)))
             (stack-remove! parser existing)))
         (formatting-reconstruct! parser)
         (formatting-push! parser (element-insert-token! parser token)))
        ((string-set-member? formatting-elements name)
         (when (and (string=? name "nobr") (element-in-default-scope? parser "nobr"))
           (adoption-agency parser "nobr"))
         (formatting-reconstruct! parser)
         (formatting-push! parser (element-insert-token! parser token)))
        ((member name '("applet" "marquee" "object"))
         (formatting-reconstruct! parser)
         (element-insert-token! parser token)
         (formatting-marker-insert! parser)
         (parser-frameset-ok-set! parser #f))
        ((string=? name "table")
         (when (and (not (eq? (parser-quirks parser) 'quirks))
                    (element-in-button-scope? parser "p"))
           (paragraph-close! parser))
         (element-insert-token! parser token)
         (parser-frameset-ok-set! parser #f)
         (parser-mode-set! parser 'in-table))
        ((member name '("area" "br" "embed" "img" "keygen" "wbr"))
         (formatting-reconstruct! parser)
         (void-element-insert! parser token)
         (parser-frameset-ok-set! parser #f))
        ((string=? name "input")
         (formatting-reconstruct! parser)
         (void-element-insert! parser token)
         (let ((type (assoc "type" attributes)))
           (unless (and type (string-ascii-equal? (cdr type) "hidden"))
             (parser-frameset-ok-set! parser #f))))
        ((member name '("param" "source" "track")) (void-element-insert! parser token))
        ((string=? name "hr")
         (when (element-in-button-scope? parser "p") (paragraph-close! parser))
         (void-element-insert! parser token)
         (parser-frameset-ok-set! parser #f))
        ((string=? name "image")
         (in-body-start-tag parser (token-start-tag-make "img" attributes
                                                         (token-start-tag-self-closing? token))))
        ((string=? name "textarea")
         (element-insert-token! parser token)
         (parser-skip-newline-set! parser #t)
         (html-tokenizer-last-start-tag-set! (parser-tokenizer parser) name)
         (html-tokenizer-state-set! (parser-tokenizer parser) 'rcdata)
         (parser-original-mode-set! parser (parser-mode parser))
         (parser-frameset-ok-set! parser #f)
         (parser-mode-set! parser 'text))
        ((string=? name "xmp")
         (when (element-in-button-scope? parser "p") (paragraph-close! parser))
         (formatting-reconstruct! parser)
         (parser-frameset-ok-set! parser #f)
         (generic-rawtext-parse! parser token 'rawtext))
        ((string=? name "iframe")
         (parser-frameset-ok-set! parser #f)
         (generic-rawtext-parse! parser token 'rawtext))
        ((or (string=? name "noembed")
             (and (string=? name "noscript") (parser-scripting? parser)))
         (generic-rawtext-parse! parser token 'rawtext))
        ((string=? name "select")
         (formatting-reconstruct! parser)
         (element-insert-token! parser token)
         (parser-frameset-ok-set! parser #f)
         (parser-mode-set!
           parser
           (if (memq (parser-mode parser)
                     '(in-table in-caption in-table-body in-row in-cell))
             'in-select-in-table
             'in-select)))
        ((member name '("optgroup" "option"))
         (when (node-html-element? (parser-current parser) "option")
           (stack-pop! parser))
         (formatting-reconstruct! parser)
         (element-insert-token! parser token))
        ((member name '("rb" "rtc"))
         (when (element-in-default-scope? parser "ruby")
           (implied-end-tags-generate! parser #f))
         (element-insert-token! parser token))
        ((member name '("rp" "rt"))
         (when (element-in-default-scope? parser "ruby")
           (implied-end-tags-generate! parser "rtc"))
         (element-insert-token! parser token))
        ((string=? name "math")
         (formatting-reconstruct! parser)
         (let ((node (element-insert!
                      parser "math" 'math
                      (attributes-adjust-foreign
                        (attributes-adjust-mathml attributes)))))
           (html-tokenizer-state-set! (parser-tokenizer parser) 'data)
           (when (token-start-tag-self-closing? token) (stack-pop! parser))))
        ((string=? name "svg")
         (formatting-reconstruct! parser)
         (let ((node (element-insert!
                      parser "svg" 'svg
                      (attributes-adjust-foreign
                        (attributes-adjust-svg attributes)))))
           (html-tokenizer-state-set! (parser-tokenizer parser) 'data)
           (when (token-start-tag-self-closing? token) (stack-pop! parser))))
        ((string-set-member? paragraph-closing-start-tags name)
         (when (element-in-button-scope? parser "p") (paragraph-close! parser))
         (element-insert-token! parser token))
        ((member name '("caption" "col" "colgroup" "frame" "head" "tbody" "td"
                        "tfoot" "th" "thead" "tr"))
         #f)
        (else
         (formatting-reconstruct! parser)
         (element-insert-token! parser token)))))

  ;; justhtml accepts a <frameset> only when everything already in the body is
  ;; frameset-neutral (engine.py, _body_allows_frameset).
  (define frameset-body-ok-names
    (names->hashtable
      '("div" "figure" "p" "param" "source" "track"
        "a" "b" "big" "code" "em" "font" "i" "nobr" "s" "small" "strike"
        "strong" "tt" "u")))

  (define (frameset-body-allowed? node)
    (let loop ((children (html-node-children node)))
      (cond
        ((null? children) #t)
        (else
         (let ((child (car children)))
           (cond
             ((node-text? child)
              (and (string-all-space? (html-node-data child)) (loop (cdr children))))
             ((not (node-element? child)) #f)
             ((not (eq? (html-node-namespace child) 'html))
              (and (frameset-foreign-allowed? child) (loop (cdr children))))
             ((string=? (html-node-name child) "input")
              (let ((type (assoc "type" (html-node-attributes child))))
                (and type
                     (string-ascii-equal? (cdr type) "hidden")
                     (loop (cdr children)))))
             ((not (string-set-member? frameset-body-ok-names (html-node-name child)))
              #f)
             (else (and (frameset-body-allowed? child) (loop (cdr children))))))))))

  (define (frameset-foreign-allowed? node)
    (let loop ((children (html-node-children node)))
      (cond
        ((null? children) #t)
        ((node-text? children) #t)
        (else
         (let ((child (car children)))
           (cond
             ((node-text? child)
              (and (string-all-space?
                     (list->string
                       (let filter ((chars (string->list (html-node-data child))))
                         (cond
                           ((null? chars) '())
                           ((char=? (car chars) (integer->char #xFFFD))
                            (filter (cdr chars)))
                           (else (cons (car chars) (filter (cdr chars))))))))
                   (loop (cdr children))))
             (else (and (frameset-foreign-allowed? child) (loop (cdr children))))))))))

  (define (in-body-list-item-start parser token name)
    (let ((targets (if (string=? name "li") '("li") '("dd" "dt"))))
      (parser-frameset-ok-set! parser #f)
      (let loop ((items (reverse (parser-stack parser))))
        (cond
          ((null? items) #f)
          ((and (eq? (html-node-namespace (car items)) 'html)
                (member (html-node-name (car items)) targets))
           (implied-end-tags-generate! parser (html-node-name (car items)))
           (stack-pop-until-name! parser (html-node-name (car items))))
          ((and (eq? (html-node-namespace (car items)) 'html)
                (string-set-member? special-elements (html-node-name (car items)))
                (not (member (html-node-name (car items))
                             '("address" "div" "p"))))
           #f)
          (else (loop (cdr items)))))
      (when (element-in-button-scope? parser "p") (paragraph-close! parser))
      (element-insert-token! parser token)))

  (define (in-body-end-tag parser token)
    (let ((name (token-end-tag-name token)))
      (cond
        ((string=? name "template") (mode-in-head parser token))
        ((string=? name "body")
         (when (element-in-default-scope? parser "body")
           (parser-mode-set! parser 'after-body)))
        ((string=? name "html")
         (when (element-in-default-scope? parser "body")
           (parser-mode-set! parser 'after-body)
           (token-reprocess parser token)))
        ((string-set-member? block-end-tags name)
         (when (element-in-default-scope? parser name)
           (implied-end-tags-generate! parser #f)
           (stack-pop-until-name! parser name)))
        ((string=? name "form")
         (cond
           ((stack-find-name parser "template")
            (when (element-in-default-scope? parser "form")
              (implied-end-tags-generate! parser #f)
              (stack-pop-until-name! parser "form")))
           (else
            (let ((form (parser-form parser)))
              (parser-form-set! parser #f)
              (when (and form (stack-contains? parser form)
                         (element-in-default-scope? parser "form"))
                (implied-end-tags-generate! parser #f)
                (stack-remove! parser form))))))
        ((string=? name "p")
         (unless (element-in-button-scope? parser "p")
           (element-insert! parser "p" 'html '()))
         (paragraph-close! parser))
        ((string=? name "li")
         (when (element-in-list-item-scope? parser "li")
           (implied-end-tags-generate! parser "li")
           (stack-pop-until-name! parser "li")))
        ((member name '("dd" "dt"))
         (when (element-in-default-scope? parser name)
           (implied-end-tags-generate! parser name)
           (stack-pop-until-name! parser name)))
        ((string-set-member? heading-elements name)
         (when (element-in-scope? parser '("h1" "h2" "h3" "h4" "h5" "h6") #f)
           (implied-end-tags-generate! parser #f)
           (let loop ()
             (let ((current (parser-current parser)))
               (cond
                 ((not current) #f)
                 ((and (eq? (html-node-namespace current) 'html)
                       (string-set-member? heading-elements (html-node-name current)))
                  (stack-pop! parser))
                 (else (stack-pop! parser) (loop)))))))
        ((string-set-member? formatting-elements name) (adoption-agency parser name))
        ((member name '("applet" "marquee" "object"))
         (when (element-in-default-scope? parser name)
           (implied-end-tags-generate! parser #f)
           (stack-pop-until-name! parser name)
           (formatting-clear-to-marker! parser)))
        ((string=? name "br")
         (in-body-start-tag parser (token-start-tag-make "br" '() #f)))
        (else (in-body-any-other-end-tag parser name)))))

  (define (in-body-any-other-end-tag parser name)
    (let loop ((items (reverse (parser-stack parser))))
      (cond
        ((null? items) #f)
        ((and (eq? (html-node-namespace (car items)) 'html)
              (string=? (html-node-name (car items)) name))
         (implied-end-tags-generate! parser name)
         (stack-pop-until-node! parser (car items)))
        ((and (eq? (html-node-namespace (car items)) 'html)
              (string-set-member? special-elements (html-node-name (car items))))
         #f)
        (else (loop (cdr items))))))

  ;; 13.2.6.4.7 the adoption agency algorithm

  (define (adoption-agency parser subject)
    (let ((current (parser-current parser)))
      (if (and current
               (node-html-element? current subject)
               (not (memq current (parser-formatting parser))))
        (stack-pop! parser)
        (adoption-agency-loop parser subject 0))))

  (define (adoption-agency-loop parser subject counter)
    (when (fx< counter 8)
      (let ((formatting-element (formatting-find-after-marker parser subject)))
        (cond
          ((not formatting-element) (in-body-any-other-end-tag parser subject))
          ((not (stack-contains? parser formatting-element))
           (parser-formatting-set! parser
                                   (remq formatting-element
                                         (parser-formatting parser))))
          ((not (element-in-default-scope? parser subject)) #f)
          (else
           (let* ((stack (parser-stack parser))
                  (formatting-index (list-index-of stack formatting-element))
                  (furthest-block
                   (let loop ((index (fx+ formatting-index 1)))
                     (cond
                       ((fx>= index (length stack)) #f)
                       ((let ((node (list-ref stack index)))
                          (and (eq? (html-node-namespace node) 'html)
                               (not (string=? (html-node-name node) "dialog"))
                               (string-set-member? special-elements
                                                   (html-node-name node))))
                        (list-ref stack index))
                       (else (loop (fx+ index 1)))))))
             (cond
               ((not furthest-block)
                (stack-pop-until-node! parser formatting-element)
                (parser-formatting-set! parser
                                        (remq formatting-element
                                              (parser-formatting parser))))
               (else
                (adoption-agency-step parser subject formatting-element
                                      furthest-block formatting-index)
                (adoption-agency-loop parser subject (fx+ counter 1))))))))))

  (define (adoption-agency-step parser subject formatting-element furthest-block
                                formatting-index)
    (let* ((stack (parser-stack parser))
           (common-ancestor (list-ref stack (fx- formatting-index 1)))
           (bookmark (list-index-of (parser-formatting parser) formatting-element)))
      (let loop ((node furthest-block)
                 (last-node furthest-block)
                 (bookmark bookmark)
                 (inner 0))
        (let* ((stack (parser-stack parser))
               (node-index (list-index-of stack node))
               (above (and node-index (fx> node-index 0)
                           (list-ref stack (fx- node-index 1)))))
          (cond
            ((not above)
             (adoption-agency-finish parser formatting-element furthest-block
                                     common-ancestor last-node bookmark))
            ((eq? above formatting-element)
             (adoption-agency-finish parser formatting-element furthest-block
                                     common-ancestor last-node bookmark))
            (else
             (let* ((inner (fx+ inner 1))
                    (node above))
               (when (and (fx> inner 3) (memq node (parser-formatting parser)))
                 (parser-formatting-set! parser
                                         (remq node (parser-formatting parser))))
               (cond
                 ((not (memq node (parser-formatting parser)))
                  (stack-remove! parser node)
                  (loop node last-node bookmark inner))
                 (else
                  (let* ((replacement (element-node-make (html-node-name node)
                                                         (html-node-namespace node)
                                                         (html-node-attributes node)))
                         (formatting-position (list-index-of (parser-formatting parser)
                                                             node))
                         (stack-position (list-index-of (parser-stack parser) node)))
                    (parser-formatting-set!
                      parser
                      (list-replace-at (parser-formatting parser)
                                       formatting-position replacement))
                    (parser-stack-set!
                      parser
                      (list-replace-at (parser-stack parser)
                                       stack-position replacement))
                    (let ((bookmark (if (eq? last-node furthest-block)
                                      (fx+ (list-index-of (parser-formatting parser)
                                                          replacement)
                                           1)
                                      bookmark)))
                      (node-append-child! replacement last-node)
                      (loop replacement replacement bookmark inner))))))))))))

  (define (adoption-agency-finish parser formatting-element furthest-block
                                  common-ancestor last-node bookmark)
    (node-insert-at! parser last-node common-ancestor)
    (let ((replacement (element-node-make (html-node-name formatting-element)
                                          (html-node-namespace formatting-element)
                                          (html-node-attributes formatting-element))))
      (for-each (lambda (child) (node-append-child! replacement child))
                (html-node-children furthest-block))
      (node-append-child! furthest-block replacement)
      (let* ((items (parser-formatting parser))
             (formatting-position (list-index-of items formatting-element))
             (bookmark (if (and formatting-position (fx< formatting-position bookmark))
                         (fx- bookmark 1)
                         bookmark))
             (items (if formatting-position
                      (list-remove-at items formatting-position)
                      items))
             (bookmark (fxmin (fxmax bookmark 0) (length items))))
        (parser-formatting-set! parser (list-insert-at items bookmark replacement)))
      (let* ((stack (remq formatting-element (parser-stack parser)))
             (block-position (list-index-of stack furthest-block)))
        (parser-stack-set! parser
                           (list-insert-at stack (fx+ block-position 1) replacement)))))

  ;; 13.2.6.4.8 "text"

  (define (mode-text parser token)
    (cond
      ((token-character? token)
       (characters-insert! parser (newline-skip parser (token-character-text token))))
      ((token-end-tag? token)
       (stack-pop! parser)
       (parser-mode-set! parser (parser-original-mode parser)))
      ((token-end-of-file? token)
       (stack-pop! parser)
       (parser-mode-set! parser (parser-original-mode parser))
       (token-reprocess parser token))
      (else #f)))

  ;; 13.2.6.4.9 "in table"

  (define (table-context-clear! parser names)
    (let loop ()
      (let ((current (parser-current parser)))
        (when (and current
                   (node-element? current)
                   (not (and (eq? (html-node-namespace current) 'html)
                             (string-set-member? names (html-node-name current)))))
          (stack-pop! parser)
          (loop)))))

  (define (mode-in-table parser token)
    (cond
      ((and (token-character? token)
            (let ((current (parser-current parser)))
              (and current
                   (eq? (html-node-namespace current) 'html)
                   (member (html-node-name current)
                           '("table" "tbody" "tfoot" "thead" "tr")))))
       (parser-table-text-set! parser '())
       (parser-original-mode-set! parser (parser-mode parser))
       (parser-mode-set! parser 'in-table-text)
       (token-reprocess parser token))
      ((token-comment-like? token) (comment-insert! parser token))
      ((token-doctype? token) #f)
      ((token-start-tag? token)
       (let ((name (token-start-tag-name token)))
         (cond
           ((string=? name "caption")
            (table-context-clear! parser table-context-clear-names)
            (formatting-marker-insert! parser)
            (element-insert-token! parser token)
            (parser-mode-set! parser 'in-caption))
           ((string=? name "colgroup")
            (table-context-clear! parser table-context-clear-names)
            (element-insert-token! parser token)
            (parser-mode-set! parser 'in-column-group))
           ((string=? name "col")
            (table-context-clear! parser table-context-clear-names)
            (element-insert! parser "colgroup" 'html '())
            (parser-mode-set! parser 'in-column-group)
            (token-reprocess parser token))
           ((member name '("tbody" "tfoot" "thead"))
            (table-context-clear! parser table-context-clear-names)
            (element-insert-token! parser token)
            (parser-mode-set! parser 'in-table-body))
           ((member name '("td" "th" "tr"))
            (table-context-clear! parser table-context-clear-names)
            (element-insert! parser "tbody" 'html '())
            (parser-mode-set! parser 'in-table-body)
            (token-reprocess parser token))
           ((string=? name "table")
            (when (element-in-table-scope? parser '("table"))
              (stack-pop-until-name! parser "table")
              (insertion-mode-reset! parser)
              (token-reprocess parser token)))
           ((member name '("style" "script" "template")) (mode-in-head parser token))
           ((string=? name "input")
            (let ((type (assoc "type" (token-start-tag-attributes token))))
              (if (and type (string-ascii-equal? (cdr type) "hidden"))
                (void-element-insert! parser token)
                (in-table-default parser token))))
           ((string=? name "form")
            ;; Inside a template that is already in a table-ish mode justhtml
            ;; still opens (and immediately closes) the form, where the spec
            ;; would drop it because a template is on the stack.
            (cond
              ((memq (list-last (parser-template-modes parser))
                     '(in-table in-table-body in-row))
               (element-insert-token! parser token)
               (stack-pop! parser))
              ((or (stack-find-name parser "template") (parser-form parser)) #f)
              (else
               (let ((node (element-insert-token! parser token)))
                 (parser-form-set! parser node)
                 (stack-pop! parser)))))
           (else (in-table-default parser token)))))
      ((token-end-tag? token)
       (let ((name (token-end-tag-name token)))
         (cond
           ((string=? name "table")
            (when (element-in-table-scope? parser '("table"))
              (stack-pop-until-name! parser "table")
              (insertion-mode-reset! parser)))
           ((member name '("body" "caption" "col" "colgroup" "html" "tbody" "td"
                           "tfoot" "th" "thead" "tr"))
            #f)
           ((string=? name "template") (mode-in-head parser token))
           (else (in-table-default parser token)))))
      ((token-end-of-file? token) (mode-in-body parser token))
      (else (in-table-default parser token))))

  (define (in-table-default parser token)
    (parser-foster-set! parser #t)
    (mode-in-body parser token)
    (parser-foster-set! parser #f))

  ;; 13.2.6.4.10 "in table text"

  (define (mode-in-table-text parser token)
    (cond
      ((token-character? token)
       (parser-table-text-set! parser
                               (append (parser-table-text parser)
                                       (list (string-nul-drop
                                               (token-character-text token))))))
      (else
       (let ((text (apply string-append (parser-table-text parser))))
         (parser-table-text-set! parser '())
         (parser-mode-set! parser (parser-original-mode parser))
         (unless (string=? text "")
           (if (string-all-space? text)
             (characters-insert! parser text)
             (in-table-default parser (token-character-make text))))
         (token-reprocess parser token)))))

  ;; 13.2.6.4.11 "in caption"

  (define (caption-close! parser)
    (implied-end-tags-generate! parser #f)
    (stack-pop-until-name! parser "caption")
    (formatting-clear-to-marker! parser)
    (parser-mode-set! parser 'in-table))

  (define (mode-in-caption parser token)
    (cond
      ((and (token-end-tag? token) (string=? (token-end-tag-name token) "caption"))
       (when (element-in-table-scope? parser '("caption")) (caption-close! parser)))
      ((and (token-start-tag? token)
            (member (token-start-tag-name token)
                    '("caption" "col" "colgroup" "tbody" "td" "tfoot" "th"
                      "thead" "tr")))
       (when (element-in-table-scope? parser '("caption"))
         (caption-close! parser)
         (token-reprocess parser token)))
      ((and (token-end-tag? token) (string=? (token-end-tag-name token) "table"))
       (when (element-in-table-scope? parser '("caption"))
         (caption-close! parser)
         (token-reprocess parser token)))
      ((and (token-end-tag? token)
            (member (token-end-tag-name token)
                    '("body" "col" "colgroup" "html" "tbody" "td" "tfoot" "th"
                      "thead" "tr")))
       #f)
      (else (mode-in-body parser token))))

  ;; 13.2.6.4.12 "in column group"

  (define (mode-in-column-group parser token)
    (cond
      ((token-character? token)
       (call-with-values
         (lambda () (string-leading-space-split (token-character-text token)))
         (lambda (space rest)
           (characters-insert! parser space)
           (unless (string=? rest "")
             (in-column-group-default parser (token-character-make rest))))))
      ((token-comment-like? token) (comment-insert! parser token))
      ((token-doctype? token) #f)
      ((and (token-start-tag? token) (string=? (token-start-tag-name token) "html"))
       (mode-in-body parser token))
      ((and (token-start-tag? token) (string=? (token-start-tag-name token) "col"))
       (void-element-insert! parser token))
      ((and (token-end-tag? token) (string=? (token-end-tag-name token) "colgroup"))
       (when (node-html-element? (parser-current parser) "colgroup")
         (stack-pop! parser)
         (parser-mode-set! parser 'in-table)))
      ((and (token-end-tag? token) (string=? (token-end-tag-name token) "col")) #f)
      ((or (and (token-start-tag? token)
                (string=? (token-start-tag-name token) "template"))
           (and (token-end-tag? token)
                (string=? (token-end-tag-name token) "template")))
       (mode-in-head parser token))
      ((token-end-of-file? token) (mode-in-body parser token))
      (else (in-column-group-default parser token))))

  (define (in-column-group-default parser token)
    (when (node-html-element? (parser-current parser) "colgroup")
      (stack-pop! parser)
      (parser-mode-set! parser 'in-table)
      (token-reprocess parser token)))

  ;; 13.2.6.4.13 "in table body"

  (define (mode-in-table-body parser token)
    (cond
      ((and (token-start-tag? token) (string=? (token-start-tag-name token) "tr"))
       (table-context-clear! parser table-body-context-clear-names)
       (element-insert-token! parser token)
       (parser-mode-set! parser 'in-row))
      ((and (token-start-tag? token)
            (member (token-start-tag-name token) '("th" "td")))
       (table-context-clear! parser table-body-context-clear-names)
       (element-insert! parser "tr" 'html '())
       (parser-mode-set! parser 'in-row)
       (token-reprocess parser token))
      ((and (token-end-tag? token)
            (member (token-end-tag-name token) '("tbody" "tfoot" "thead")))
       (when (element-in-table-scope? parser (list (token-end-tag-name token)))
         (table-context-clear! parser table-body-context-clear-names)
         (stack-pop! parser)
         (parser-mode-set! parser 'in-table)))
      ((or (and (token-start-tag? token)
                (member (token-start-tag-name token)
                        '("caption" "col" "colgroup" "tbody" "tfoot" "thead")))
           (and (token-end-tag? token)
                (string=? (token-end-tag-name token) "table")))
       (when (element-in-table-scope? parser '("tbody" "thead" "tfoot"))
         (table-context-clear! parser table-body-context-clear-names)
         (stack-pop! parser)
         (parser-mode-set! parser 'in-table)
         (token-reprocess parser token)))
      ((and (token-end-tag? token)
            (member (token-end-tag-name token)
                    '("body" "caption" "col" "colgroup" "html" "td" "th" "tr")))
       #f)
      (else (mode-in-table parser token))))

  ;; 13.2.6.4.14 "in row"

  (define (mode-in-row parser token)
    (cond
      ((and (token-start-tag? token)
            (member (token-start-tag-name token) '("th" "td")))
       (table-context-clear! parser table-row-context-clear-names)
       (element-insert-token! parser token)
       (parser-mode-set! parser 'in-cell)
       (formatting-marker-insert! parser))
      ((and (token-end-tag? token) (string=? (token-end-tag-name token) "tr"))
       (when (element-in-table-scope? parser '("tr"))
         (table-context-clear! parser table-row-context-clear-names)
         (stack-pop! parser)
         (parser-mode-set! parser 'in-table-body)))
      ((or (and (token-start-tag? token)
                (member (token-start-tag-name token)
                        '("caption" "col" "colgroup" "tbody" "tfoot" "thead" "tr")))
           (and (token-end-tag? token)
                (string=? (token-end-tag-name token) "table")))
       (when (element-in-table-scope? parser '("tr"))
         (table-context-clear! parser table-row-context-clear-names)
         (stack-pop! parser)
         (parser-mode-set! parser 'in-table-body)
         (token-reprocess parser token)))
      ((and (token-end-tag? token)
            (member (token-end-tag-name token) '("tbody" "tfoot" "thead")))
       (when (and (element-in-table-scope? parser (list (token-end-tag-name token)))
                  (element-in-table-scope? parser '("tr")))
         (table-context-clear! parser table-row-context-clear-names)
         (stack-pop! parser)
         (parser-mode-set! parser 'in-table-body)
         (token-reprocess parser token)))
      ((and (token-end-tag? token)
            (member (token-end-tag-name token)
                    '("body" "caption" "col" "colgroup" "html" "td" "th")))
       #f)
      (else (mode-in-table parser token))))

  ;; 13.2.6.4.15 "in cell"

  (define (cell-close! parser)
    (let ((name (let loop ((items (reverse (parser-stack parser))))
                  (cond
                    ((null? items) #f)
                    ((and (eq? (html-node-namespace (car items)) 'html)
                          (member (html-node-name (car items)) '("td" "th")))
                     (html-node-name (car items)))
                    (else (loop (cdr items)))))))
      (when name
        (implied-end-tags-generate! parser #f)
        (stack-pop-until-name! parser name)
        (formatting-clear-to-marker! parser)
        (parser-mode-set! parser 'in-row))))

  (define (mode-in-cell parser token)
    (cond
      ((and (token-end-tag? token)
            (member (token-end-tag-name token) '("td" "th")))
       (when (element-in-table-scope? parser (list (token-end-tag-name token)))
         (implied-end-tags-generate! parser #f)
         (stack-pop-until-name! parser (token-end-tag-name token))
         (formatting-clear-to-marker! parser)
         (parser-mode-set! parser 'in-row)))
      ((and (token-start-tag? token)
            (member (token-start-tag-name token)
                    '("caption" "col" "colgroup" "tbody" "td" "tfoot" "th"
                      "thead" "tr")))
       (when (element-in-table-scope? parser '("td" "th"))
         (cell-close! parser)
         (token-reprocess parser token)))
      ((and (token-end-tag? token)
            (member (token-end-tag-name token) '("body" "caption" "col" "colgroup"
                                                 "html")))
       #f)
      ((and (token-end-tag? token)
            (member (token-end-tag-name token)
                    '("table" "tbody" "tfoot" "thead" "tr")))
       (when (element-in-table-scope? parser (list (token-end-tag-name token)))
         (cell-close! parser)
         (token-reprocess parser token)))
      (else (mode-in-body parser token))))

  ;; 13.2.6.4.16 "in select"

  (define (select-close! parser)
    (stack-pop-until-name! parser "select")
    (insertion-mode-reset! parser))

  (define (mode-in-select parser token)
    (cond
      ((token-character? token)
       (let ((text (string-nul-drop (token-character-text token))))
         (characters-insert! parser text)))
      ((token-comment-like? token) (comment-insert! parser token))
      ((token-doctype? token) #f)
      ((token-start-tag? token)
       (let ((name (token-start-tag-name token)))
         (cond
           ((string=? name "html") (mode-in-body parser token))
           ((string=? name "option")
            (when (node-html-element? (parser-current parser) "option")
              (stack-pop! parser))
            (element-insert-token! parser token))
           ((string=? name "optgroup")
            (when (node-html-element? (parser-current parser) "option")
              (stack-pop! parser))
            (when (node-html-element? (parser-current parser) "optgroup")
              (stack-pop! parser))
            (element-insert-token! parser token))
           ((string=? name "hr")
            (when (node-html-element? (parser-current parser) "option")
              (stack-pop! parser))
            (when (node-html-element? (parser-current parser) "optgroup")
              (stack-pop! parser))
            (void-element-insert! parser token))
           ((string=? name "select")
            (when (element-in-select-scope? parser "select") (select-close! parser)))
           ((member name '("input" "keygen" "textarea"))
            (when (element-in-select-scope? parser "select")
              (select-close! parser)
              (token-reprocess parser token)))
           ((member name '("script" "template")) (mode-in-head parser token))
           ;; justhtml keeps arbitrary content inside <select> rather than
           ;; dropping it, matching the customizable-select shape of the
           ;; fixtures in select_recovery.dat and selectedcontent.dat.
           (else (mode-in-body parser token)))))
      ((token-end-tag? token)
       (let ((name (token-end-tag-name token)))
         (cond
           ((string=? name "optgroup")
            (let* ((stack (parser-stack parser))
                   (size (length stack)))
              (when (and (fx>= size 2)
                         (node-html-element? (list-ref stack (fx- size 1)) "option")
                         (node-html-element? (list-ref stack (fx- size 2)) "optgroup"))
                (stack-pop! parser)))
            (when (node-html-element? (parser-current parser) "optgroup")
              (stack-pop! parser)))
           ((string=? name "option")
            (when (node-html-element? (parser-current parser) "option")
              (stack-pop! parser)))
           ((string=? name "select")
            (when (element-in-select-scope? parser "select") (select-close! parser)))
           ((string=? name "template") (mode-in-head parser token))
           ;; An end tag for an element opened before the <select> is dropped;
           ;; anything opened inside it closes normally (justhtml engine.py
           ;; line 2901).
           ((select-encloses-name? parser name) #f)
           (else (mode-in-body parser token)))))
      ((token-end-of-file? token) (mode-in-body parser token))
      (else #f)))

  (define (select-encloses-name? parser name)
    (let* ((stack (parser-stack parser))
           (select-index
            (let loop ((index (fx- (length stack) 1)))
              (cond
                ((fx< index 0) #f)
                ((node-html-element? (list-ref stack index) "select") index)
                (else (loop (fx- index 1))))))
           (target-index
            (let loop ((index (fx- (length stack) 1)))
              (cond
                ((fx< index 0) #f)
                ((let ((node (list-ref stack index)))
                   (and (node-element? node) (string=? (html-node-name node) name)))
                 index)
                (else (loop (fx- index 1)))))))
      (and select-index target-index (fx< target-index select-index))))

  ;; 13.2.6.4.17 "in select in table"

  (define (mode-in-select-in-table parser token)
    (cond
      ((and (token-start-tag? token)
            (member (token-start-tag-name token)
                    '("caption" "table" "tbody" "tfoot" "thead" "tr" "td" "th")))
       (select-close! parser)
       (token-reprocess parser token))
      ((and (token-end-tag? token)
            (member (token-end-tag-name token)
                    '("caption" "table" "tbody" "tfoot" "thead" "tr" "td" "th")))
       (when (element-in-table-scope? parser (list (token-end-tag-name token)))
         (select-close! parser)
         (token-reprocess parser token)))
      (else (mode-in-select parser token))))

  ;; 13.2.6.4.18 "in template"

  (define (template-mode-switch! parser mode)
    (let ((modes (parser-template-modes parser)))
      (unless (null? modes)
        (parser-template-modes-set! parser
                                    (list-remove-at modes (fx- (length modes) 1)))))
    (parser-template-modes-set! parser
                                (append (parser-template-modes parser) (list mode)))
    (parser-mode-set! parser mode))

  (define (mode-in-template parser token)
    (cond
      ((or (token-character? token) (token-comment-like? token) (token-doctype? token))
       (mode-in-body parser token))
      ((token-start-tag? token)
       (let ((name (token-start-tag-name token)))
         (cond
           ((string=? name "template") (mode-in-head parser token))
           ;; Head content and the raw-text/RCDATA elements move the template
           ;; out of its initial mode, so later table structure is ignored
           ;; instead of opened.
           ((or (string-set-member? head-content-start-tags name)
                (member name '("iframe" "noembed" "noscript" "xmp" "textarea")))
            (template-mode-switch! parser 'in-body)
            (token-reprocess parser token))
           ((member name '("caption" "colgroup" "tbody" "tfoot" "thead"))
            (template-mode-switch! parser 'in-table)
            (token-reprocess parser token))
           ((string=? name "col")
            (template-mode-switch! parser 'in-column-group)
            (token-reprocess parser token))
           ((string=? name "tr")
            (template-mode-switch! parser 'in-table-body)
            (token-reprocess parser token))
           ((member name '("td" "th"))
            (template-mode-switch! parser 'in-row)
            (token-reprocess parser token))
           (else
            (template-mode-switch! parser 'in-body)
            (token-reprocess parser token)))))
      ((token-end-tag? token)
       (if (string=? (token-end-tag-name token) "template")
         (mode-in-head parser token)
         #f))
      ((token-end-of-file? token)
       (if (not (stack-find-name parser "template"))
         (parser-done-set! parser #t)
         (begin
           (stack-pop-until-name! parser "template")
           (formatting-clear-to-marker! parser)
           (let ((modes (parser-template-modes parser)))
             (unless (null? modes)
               (parser-template-modes-set!
                 parser (list-remove-at modes (fx- (length modes) 1)))))
           (insertion-mode-reset! parser)
           (token-reprocess parser token))))
      (else #f)))

  ;; 13.2.6.4.19 "after body"

  (define (mode-after-body parser token)
    (cond
      ((token-character? token)
       (call-with-values
         (lambda () (string-leading-space-split (token-character-text token)))
         (lambda (space rest)
           (unless (string=? space "")
             (mode-in-body parser (token-character-make space)))
           (unless (string=? rest "")
             (parser-mode-set! parser 'in-body)
             (token-reprocess parser (token-character-make rest))))))
      ((token-comment-like? token)
       (comment-append-to! parser token (car (parser-stack parser))))
      ((token-doctype? token) #f)
      ((and (token-start-tag? token) (string=? (token-start-tag-name token) "html"))
       (mode-in-body parser token))
      ((and (token-end-tag? token) (string=? (token-end-tag-name token) "html"))
       (if (parser-fragment? parser)
         #f
         (parser-mode-set! parser 'after-after-body)))
      ((token-end-of-file? token) (parser-done-set! parser #t))
      (else
       (parser-mode-set! parser 'in-body)
       (token-reprocess parser token))))

  ;; 13.2.6.4.20 "in frameset"

  (define (mode-in-frameset parser token)
    (cond
      ((token-character? token)
       (call-with-values
         (lambda () (string-leading-space-split (token-character-text token)))
         (lambda (space rest) (characters-insert! parser space))))
      ((token-comment-like? token) (comment-insert! parser token))
      ((token-doctype? token) #f)
      ((and (token-start-tag? token) (string=? (token-start-tag-name token) "html"))
       (mode-in-body parser token))
      ((and (token-start-tag? token) (string=? (token-start-tag-name token) "frameset"))
       (element-insert-token! parser token))
      ((and (token-end-tag? token) (string=? (token-end-tag-name token) "frameset"))
       (unless (node-html-element? (parser-current parser) "html")
         (stack-pop! parser)
         (when (and (not (parser-fragment? parser))
                    (not (node-html-element? (parser-current parser) "frameset")))
           (parser-mode-set! parser 'after-frameset))))
      ((and (token-start-tag? token) (string=? (token-start-tag-name token) "frame"))
       (void-element-insert! parser token))
      ((and (token-start-tag? token) (string=? (token-start-tag-name token) "noframes"))
       (mode-in-head parser token))
      ((token-end-of-file? token) (parser-done-set! parser #t))
      (else #f)))

  ;; 13.2.6.4.21 "after frameset"

  (define (mode-after-frameset parser token)
    (cond
      ((token-character? token)
       (call-with-values
         (lambda () (string-leading-space-split (token-character-text token)))
         (lambda (space rest) (characters-insert! parser space))))
      ((token-comment-like? token) (comment-insert! parser token))
      ((token-doctype? token) #f)
      ((and (token-start-tag? token) (string=? (token-start-tag-name token) "html"))
       (mode-in-body parser token))
      ((and (token-end-tag? token) (string=? (token-end-tag-name token) "html"))
       (parser-mode-set! parser 'after-after-frameset))
      ((and (token-start-tag? token) (string=? (token-start-tag-name token) "noframes"))
       (mode-in-head parser token))
      ((token-end-of-file? token) (parser-done-set! parser #t))
      (else #f)))

  ;; 13.2.6.4.22 "after after body"

  (define (mode-after-after-body parser token)
    (cond
      ((token-comment-like? token)
       (comment-append-to! parser token (parser-document parser)))
      ((token-doctype? token) (mode-in-body parser token))
      ((token-character? token)
       (call-with-values
         (lambda () (string-leading-space-split (token-character-text token)))
         (lambda (space rest)
           (unless (string=? space "")
             (mode-in-body parser (token-character-make space)))
           (unless (string=? rest "")
             (parser-mode-set! parser 'in-body)
             (token-reprocess parser (token-character-make rest))))))
      ((and (token-start-tag? token) (string=? (token-start-tag-name token) "html"))
       (mode-in-body parser token))
      ((token-end-of-file? token) (parser-done-set! parser #t))
      (else
       (parser-mode-set! parser 'in-body)
       (token-reprocess parser token))))

  ;; 13.2.6.4.23 "after after frameset"

  (define (mode-after-after-frameset parser token)
    (cond
      ((token-comment-like? token)
       (comment-append-to! parser token (parser-document parser)))
      ((token-doctype? token) (mode-in-body parser token))
      ((token-character? token)
       (call-with-values
         (lambda () (string-leading-space-split (token-character-text token)))
         (lambda (space rest)
           (unless (string=? space "")
             (mode-in-body parser (token-character-make space))))))
      ((and (token-start-tag? token) (string=? (token-start-tag-name token) "html"))
       (mode-in-body parser token))
      ((token-end-of-file? token) (parser-done-set! parser #t))
      ((and (token-start-tag? token) (string=? (token-start-tag-name token) "noframes"))
       (mode-in-head parser token))
      (else #f)))

  ;; ------------------------------------------------------------------
  ;; 13.2.6.5 foreign content
  ;; ------------------------------------------------------------------

  (define (foreign-breakout? token)
    (and (token-start-tag? token)
         (let ((name (token-start-tag-name token)))
           (or (string-set-member? foreign-breakout-elements name)
               (and (string=? name "font")
                    (let ((attributes (token-start-tag-attributes token)))
                      (or (assoc "color" attributes)
                          (assoc "face" attributes)
                          (assoc "size" attributes))
                      ))))))

  (define (foreign-content-process parser token)
    (cond
      ((token-character? token)
       (let* ((raw (token-character-text token))
              (text (list->string
                     (map (lambda (c)
                            (if (char=? c #\nul) (integer->char #xFFFD) c))
                          (string->list raw)))))
         (characters-insert! parser text)
         (unless (string-all-space? text)
           (parser-frameset-ok-set! parser #f))))
      ((token-comment-like? token) (comment-insert! parser token))
      ((token-doctype? token) #f)
      ((and (token-start-tag? token) (foreign-breakout? token))
       (cond
         ((parser-fragment? parser) (foreign-start-tag parser token))
         (else
          (let loop ()
            (let ((current (parser-current parser)))
              (when (and current
                         (not (and (node-element? current)
                                   (eq? (html-node-namespace current) 'html)))
                         (not (mathml-text-integration-point? current))
                         (not (html-integration-point? current)))
                (stack-pop! parser)
                (loop))))
          (token-reprocess parser token))))
      ((token-start-tag? token) (foreign-start-tag parser token))
      ((token-end-tag? token) (foreign-end-tag parser token))
      (else #f)))

  (define (foreign-start-tag parser token)
    (let* ((adjusted (parser-adjusted-current parser))
           (namespace (if (and adjusted (node-element? adjusted))
                        (html-node-namespace adjusted)
                        'html))
           (name (token-start-tag-name token))
           (attributes (token-start-tag-attributes token)))
      (let-values (((name attributes)
                    (case namespace
                      ((math) (values name (attributes-adjust-mathml attributes)))
                      ((svg) (values (svg-tag-name-adjust name)
                                     (attributes-adjust-svg attributes)))
                      (else (values name attributes)))))
        (element-insert! parser name namespace (attributes-adjust-foreign attributes))
        (html-tokenizer-state-set! (parser-tokenizer parser) 'data)
        (when (token-start-tag-self-closing? token)
          (stack-pop! parser)))))

  (define (foreign-end-tag parser token)
    (let ((name (string-ascii-lowercase (token-end-tag-name token)))
          (stack (parser-stack parser)))
      (let loop ((index (fx- (length stack) 1)))
        (cond
          ((fx< index 0) #f)
          (else
           (let ((node (list-ref stack index)))
             (cond
               ((fx= index 0) #f)
               ((string=? (string-ascii-lowercase (html-node-name node)) name)
                (stack-pop-until-node! parser node))
               (else
                (let ((next (list-ref stack (fx- index 1))))
                  (if (and (node-element? next)
                           (eq? (html-node-namespace next) 'html))
                    (mode-process parser (parser-mode parser) token)
                    (loop (fx- index 1))))))))))))

  ;; ------------------------------------------------------------------
  ;; Fragment parsing
  ;; ------------------------------------------------------------------

  (define (fragment-context-parse context)
    ;; A fragment context is either "name" or "namespace name".
    (let ((space (let loop ((i 0))
                   (cond
                     ((fx>= i (string-length context)) #f)
                     ((char=? (string-ref context i) #\space) i)
                     (else (loop (fx+ i 1)))))))
      (if space
        (let ((namespace (substring context 0 space))
              (name (substring context (fx+ space 1) (string-length context))))
          (cons (cond
                  ((string=? namespace "svg") 'svg)
                  ((string=? namespace "math") 'math)
                  (else 'html))
                name))
        (cons 'html context))))

  (define (fragment-setup! parser context)
    (let* ((parsed (fragment-context-parse context))
           (namespace (car parsed))
           (name (cdr parsed))
           (context-node (element-node-make name namespace '()))
           (root (element-node-make "html" 'html '())))
      (parser-fragment-context-set! parser context-node)
      (node-append-child! (parser-document parser) root)
      (stack-push! parser root)
      (parser-root-set! parser root)
      (when (and (eq? namespace 'html) (string=? name "template"))
        (parser-template-modes-set! parser '(in-template)))
      (insertion-mode-reset! parser)
      (when (eq? namespace 'html)
        (when (member name '("pre" "listing" "textarea"))
          (parser-skip-newline-set! parser #t))
        (let ((state (html-tokenizer-content-state-for-tag
                      name (parser-scripting? parser))))
          (unless (eq? state 'data)
            ;; No last start tag: in a fragment nothing closes the context
            ;; element, so the whole input stays text.
            (html-tokenizer-state-set! (parser-tokenizer parser) state))))))

  ;; ------------------------------------------------------------------
  ;; <selectedcontent> projection
  ;; ------------------------------------------------------------------
  ;;
  ;; A <selectedcontent> element mirrors the content of its <select>'s
  ;; selected option (justhtml engine.py, _project_select_selectedcontent).
  ;; This runs once over the finished tree.

  (define (node-clone node)
    (let ((copy (html-node-new (html-node-kind node)
                               (html-node-name node)
                               (html-node-namespace node)
                               (html-node-attributes node)
                               '() #f (html-node-data node) #f)))
      (for-each (lambda (child) (node-append-child! copy (node-clone child)))
                (html-node-children node))
      copy))

  (define (selectedcontent-project! root)
    (let loop ((node root))
      (when (node-element? node)
        (when (node-html-element? node "select")
          (select-selectedcontent-project! node)))
      (for-each loop (html-node-children node))))

  (define (select-selectedcontent-project! select)
    (let ((markers '())
          (spans '())
          (selected #f)
          (first #f)
          (multiple? (and (assoc "multiple" (html-node-attributes select)) #t))
          (position 0))
      (let walk ((node select) (disabled-optgroup? #f) (datalist? #f))
        (set! position (fx+ position 1))
        (let* ((element? (node-element? node))
               (name (and element? (html-node-name node)))
               (attributes (if element? (html-node-attributes node) '()))
               (option? (and element? (not (eq? node select))
                             (string=? name "option") (not datalist?)))
               (enter position))
          (when (and element? (not (eq? node select)))
            (when (string=? name "selectedcontent")
              (set! markers (append markers (list (cons node position)))))
            (when option?
              (when (and (not first)
                         (not disabled-optgroup?)
                         (not (assoc "disabled" attributes)))
                (set! first node))
              (when (assoc "selected" attributes)
                (if multiple?
                  (unless selected (set! selected node))
                  (set! selected node)))))
          (for-each (lambda (child)
                      (walk child
                            (or disabled-optgroup?
                                (and element?
                                     (string=? name "optgroup")
                                     (and (assoc "disabled" attributes) #t)))
                            (or datalist? (and element? (string=? name "datalist")))))
                    (html-node-children node))
          (when option?
            (set! spans (cons (list node enter position) spans)))))
      (let* ((option (or selected first))
             (span (and option (assoc option spans))))
        (unless (null? markers)
          (for-each
            (lambda (marker)
              (let ((node (car marker))
                    (marker-position (cdr marker)))
                (unless (and span
                             (fx< (cadr span) marker-position)
                             (fx<= marker-position (caddr span)))
                  (for-each (lambda (child) (html-node-parent-set! child #f))
                            (html-node-children node))
                  (html-node-children-set! node '())
                  (when option
                    (for-each (lambda (child)
                                (node-append-child! node (node-clone child)))
                              (html-node-children option))))))
            markers)))))

  ;; ------------------------------------------------------------------
  ;; Layer 6 -- entry points
  ;; ------------------------------------------------------------------

  (define (option-ref options key default)
    (let ((pair (assq key options)))
      (if pair (cdr pair) default)))

  ;; Parse and return the internal node tree (a document or, for fragment
  ;; parsing, the synthetic root element whose children are the fragment).
  (define html-parse
    (case-lambda
      ((text) (html-parse text '()))
      ((text options)
       (let* ((scripting? (option-ref options 'scripting #t))
              (iframe-srcdoc? (option-ref options 'iframe-srcdoc #f))
              (context (option-ref options 'fragment-context #f))
              (coerce? (option-ref options 'xml-coercion #f))
              (parser (parser-make (html-source-preprocess text)
                                   scripting? iframe-srcdoc? coerce?)))
         (when context (fragment-setup! parser context))
         (parser-run! parser)
         (let ((root (if context (parser-root parser) (parser-document parser))))
           (selectedcontent-project! root)
           root)))))

  ;; ------------------------------------------------------------------
  ;; Layer 5 -- SXML assembly
  ;; ------------------------------------------------------------------

  (define (html-node->sxml node)
    (case (html-node-kind node)
      ((document) (cons '*TOP* (map html-node->sxml (html-node-children node))))
      ((fragment) (cons '*CONTENT* (map html-node->sxml (html-node-children node))))
      ((text) (html-node-data node))
      ((comment) (list '*COMMENT* (html-node-data node)))
      ((processing-instruction)
       (list '*PI* (string->symbol (html-node-name node)) (html-node-data node)))
      ((doctype)
       (let ((data (html-node-data node)))
         (list '*DOCTYPE* (car data) (cadr data) (caddr data))))
      ((element)
       (let* ((attributes (html-node-attributes node))
              (children (if (html-node-content node)
                          (list (html-node->sxml (html-node-content node)))
                          (map html-node->sxml (html-node-children node))))
              (name (string->symbol (html-node-name node))))
         (if (null? attributes)
           (cons name children)
           (cons name
                 (cons (cons sxml-attribute-mark (map (lambda (pair)
                                       (list (string->symbol (car pair)) (cdr pair)))
                                     attributes))
                       children)))))
      (else (error 'html-node->sxml "unknown node kind" (html-node-kind node)))))

  ;; The layer 6 entry point.
  (define html->sxml
    (case-lambda
      ((text) (html->sxml text '()))
      ((text options)
       (let ((node (html-parse text options)))
         (if (option-ref options 'fragment-context #f)
           (cons '*TOP* (map html-node->sxml (html-node-children node)))
           (html-node->sxml node))))))

  ;; ------------------------------------------------------------------
  ;; Layer 5 -- html5lib test format serialization
  ;; ------------------------------------------------------------------

  ;; Chez's R6RS reader rejects a bare "@", so the SXML attribute marker is
  ;; spelled with the R6RS inline hex escape \x40; wherever it appears as a
  ;; literal.
  (define sxml-attribute-mark (string->symbol "@"))

  (define (sxml-element? form)
    (and (pair? form) (symbol? (car form))))

  (define (sxml-attributes form)
    (let ((rest (cdr form)))
      (if (and (pair? rest) (pair? (car rest)) (eq? (car (car rest)) sxml-attribute-mark))
        (cdr (car rest))
        '())))

  (define (sxml-children form)
    (let ((rest (cdr form)))
      (if (and (pair? rest) (pair? (car rest)) (eq? (car (car rest)) sxml-attribute-mark))
        (cdr rest)
        rest)))

  (define (sxml-attribute-ref form name)
    (let loop ((attributes (sxml-attributes form)))
      (cond
        ((null? attributes) #f)
        ((string-ascii-equal? (symbol->string (car (car attributes))) name)
         (car (cdr (car attributes))))
        (else (loop (cdr attributes))))))

  (define (element-own-namespace name parent-namespace)
    (if (eq? parent-namespace 'html)
      (cond
        ((string=? name "svg") 'svg)
        ((string=? name "math") 'math)
        (else 'html))
      parent-namespace))

  (define (element-children-namespace form name namespace)
    (case namespace
      ((svg) (if (string-set-member? svg-html-integration-names name) 'html 'svg))
      ((math)
       (cond
         ((string-set-member? mathml-text-integration-names name) 'html)
         ((and (string=? name "annotation-xml")
               (let ((encoding (sxml-attribute-ref form "encoding")))
                 (and encoding
                      (let ((value (string-ascii-lowercase encoding)))
                        (or (string=? value "text/html")
                            (string=? value "application/xhtml+xml"))))))
          'html)
         (else 'math)))
      (else 'html)))

  (define (indentation size)
    (make-string size #\space))

  (define (attribute-display-name name namespace)
    (if (and (not (eq? namespace 'html))
             (hashtable-ref foreign-attribute-adjustments
                            (string-ascii-lowercase name) #f))
      (list->string (map (lambda (c) (if (char=? c #\:) #\space c))
                         (string->list name)))
      name))

  (define (attribute-lines form namespace indent)
    (let* ((names (map (lambda (attribute)
                         (cons (attribute-display-name
                                 (symbol->string (car attribute)) namespace)
                               (car (cdr attribute))))
                       (sxml-attributes form)))
           (sorted (list-sort (lambda (a b) (string<? (car a) (car b))) names)))
      (map (lambda (pair)
             (string-append "| " (indentation indent) (car pair)
                            "=\"" (cdr pair) "\""))
           sorted)))

  (define (doctype-line form)
    (let ((name (car (cdr form)))
          (public-id (car (cddr form)))
          (system-id (car (cdddr form))))
      (string-append
        "| <!DOCTYPE"
        (if (and name (not (string=? name ""))) (string-append " " name) " ")
        (if (or public-id system-id)
          (string-append " \"" (or public-id "") "\" \"" (or system-id "") "\"")
          "")
        ">")))

  (define (node-lines form namespace indent)
    (cond
      ((string? form) (list (string-append "| " (indentation indent) "\"" form "\"")))
      ((not (pair? form)) '())
      ((eq? (car form) '*COMMENT*)
       (list (string-append "| " (indentation indent) "<!-- " (cadr form) " -->")))
      ((eq? (car form) '*PI*)
       (list (string-append "| " (indentation indent) "<?"
                            (symbol->string (cadr form)) " " (caddr form) "?>")))
      ((eq? (car form) '*DOCTYPE*) (list (doctype-line form)))
      (else
       (let* ((name (symbol->string (car form)))
              (own (element-own-namespace name namespace))
              (children-namespace (element-children-namespace form name own))
              (qualified (if (eq? own 'html)
                           name
                           (string-append (symbol->string own) " " name)))
              (line (string-append "| " (indentation indent) "<" qualified ">"))
              (attributes (attribute-lines form own (fx+ indent 2)))
              (children (sxml-children form)))
         (cond
           ;; Template content is a separate fragment; it prints as a
           ;; "content" line with the fragment's children below it.
           ((and (string=? name "template")
                 (eq? own 'html)
                 (fx= (length children) 1)
                 (pair? (car children))
                 (eq? (car (car children)) '*CONTENT*))
            (append (list line)
                    attributes
                    (list (string-append "| " (indentation (fx+ indent 2)) "content"))
                    (apply append
                           (map (lambda (child)
                                  (node-lines child children-namespace (fx+ indent 4)))
                                (cdr (car children))))))
           (else
            (append (list line)
                    attributes
                    (apply append
                           (map (lambda (child)
                                  (node-lines child children-namespace (fx+ indent 2)))
                                children)))))))))

  (define (html-sxml->test-format form)
    (let ((lines (if (and (pair? form) (eq? (car form) '*TOP*))
                   (apply append (map (lambda (child) (node-lines child 'html 0))
                                      (cdr form)))
                   (node-lines form 'html 0))))
      (let loop ((lines lines) (port (open-output-string)) (first? #t))
        (cond
          ((null? lines) (get-output-string port))
          (else
           (unless first? (write-char #\newline port))
           (put-string port (car lines))
           (loop (cdr lines) port #f))))))

  ;; ------------------------------------------------------------------
  ;; General purpose SXML -> HTML serialization
  ;; ------------------------------------------------------------------
  ;;
  ;; Independent of the html5lib test format above: renders an SXML tree back
  ;; to an HTML source string.

  (define raw-text-element-names
    (names->hashtable
      '("script" "style" "xmp" "iframe" "noembed" "noframes" "plaintext")))

  (define (html-text-escape text raw?)
    (if raw?
      text
      (let ((port (open-output-string)))
        (let loop ((i 0))
          (cond
            ((fx>= i (string-length text)) (get-output-string port))
            (else
             (let ((c (string-ref text i)))
               (cond
                 ((char=? c #\&) (put-string port "&amp;"))
                 ((char=? c #\<) (put-string port "&lt;"))
                 ((char=? c #\>) (put-string port "&gt;"))
                 ((char=? c (integer->char #xA0)) (put-string port "&nbsp;"))
                 (else (write-char c port)))
               (loop (fx+ i 1)))))))))

  (define (html-attribute-escape text)
    (let ((port (open-output-string)))
      (let loop ((i 0))
        (cond
          ((fx>= i (string-length text)) (get-output-string port))
          (else
           (let ((c (string-ref text i)))
             (cond
               ((char=? c #\&) (put-string port "&amp;"))
               ((char=? c #\") (put-string port "&quot;"))
               ((char=? c (integer->char #xA0)) (put-string port "&nbsp;"))
               (else (write-char c port)))
             (loop (fx+ i 1))))))))

  (define (html-sxml->html form)
    (let ((port (open-output-string)))
      (sxml-html-write form port #f)
      (get-output-string port)))

  (define (sxml-html-write form port raw?)
    (cond
      ((string? form) (put-string port (html-text-escape form raw?)))
      ((not (pair? form)) #f)
      ((eq? (car form) '*TOP*)
       (for-each (lambda (child) (sxml-html-write child port #f)) (cdr form)))
      ((eq? (car form) '*CONTENT*)
       (for-each (lambda (child) (sxml-html-write child port #f)) (cdr form)))
      ((eq? (car form) '*COMMENT*)
       (put-string port "<!--")
       (put-string port (cadr form))
       (put-string port "-->"))
      ((eq? (car form) '*PI*)
       (put-string port "<?")
       (put-string port (symbol->string (cadr form)))
       (put-string port " ")
       (put-string port (caddr form))
       (put-string port ">"))
      ((eq? (car form) '*DOCTYPE*)
       (let ((name (cadr form))
             (public-id (caddr form))
             (system-id (car (cdddr form))))
         (put-string port "<!DOCTYPE")
         (when (and name (not (string=? name ""))) (put-string port " ")
               (put-string port name))
         (when public-id
           (put-string port " PUBLIC \"")
           (put-string port public-id)
           (put-string port "\""))
         (when system-id
           (put-string port (if public-id " \"" " SYSTEM \""))
           (put-string port system-id)
           (put-string port "\""))
         (put-string port ">")))
      (else
       (let* ((name (symbol->string (car form)))
              (children (sxml-children form))
              (raw-child? (string-set-member? raw-text-element-names name)))
         (put-string port "<")
         (put-string port name)
         (for-each
           (lambda (attribute)
             (put-string port " ")
             (put-string port (symbol->string (car attribute)))
             (put-string port "=\"")
             (put-string port (html-attribute-escape (car (cdr attribute))))
             (put-string port "\""))
           (sxml-attributes form))
         (put-string port ">")
         (unless (string-set-member? void-elements name)
           (for-each (lambda (child) (sxml-html-write child port raw-child?))
                     children)
           (put-string port "</")
           (put-string port name)
           (put-string port ">"))))))

  (include "letloop/html/justhtml.check.scm"))
