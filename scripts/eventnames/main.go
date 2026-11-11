// eventnames extracts the plugin event-name set from a Go source file using
// the official Go parser (go/ast) — no regex source scraping.
//
// It locates the package-level `allEventNames = []string{...}` slice (the
// negotiation/delivery set), resolves each element identifier to its
// package-level const string value, and prints one event name per line in
// slice order (deduplicated). Reading the negotiation slice rather than
// grepping constants keeps the extraction faithful to the set the host
// actually negotiates and delivers.
//
// Usage:
//
//	eventnames <file.go>
//
// Exit codes: 0 = ok; 2 = usage/parse error, allEventNames missing, or an
// element could not be resolved to a const string (never a silent empty set).
package main

import (
	"fmt"
	"go/ast"
	"go/parser"
	"go/token"
	"os"
	"strconv"
)

func main() {
	if len(os.Args) < 2 {
		fmt.Fprintln(os.Stderr, "usage: eventnames <file.go>")
		os.Exit(2)
	}
	fset := token.NewFileSet()
	f, err := parser.ParseFile(fset, os.Args[1], nil, 0)
	if err != nil {
		fmt.Fprintf(os.Stderr, "parse error: %v\n", err)
		os.Exit(2)
	}

	consts := map[string]string{}
	var names []string
	found := false

	for _, decl := range f.Decls {
		gd, ok := decl.(*ast.GenDecl)
		if !ok {
			continue
		}
		switch gd.Tok {
		case token.CONST:
			for _, spec := range gd.Specs {
				vs, ok := spec.(*ast.ValueSpec)
				if !ok || len(vs.Names) == 0 || len(vs.Values) == 0 {
					continue
				}
				lit, ok := vs.Values[0].(*ast.BasicLit)
				if !ok || lit.Kind != token.STRING {
					continue
				}
				val, err := strconv.Unquote(lit.Value)
				if err != nil {
					continue
				}
				consts[vs.Names[0].Name] = val
			}
		case token.VAR:
			for _, spec := range gd.Specs {
				vs, ok := spec.(*ast.ValueSpec)
				if !ok || len(vs.Names) == 0 || vs.Names[0].Name != "allEventNames" {
					continue
				}
				if len(vs.Values) == 0 {
					continue
				}
				cl, ok := vs.Values[0].(*ast.CompositeLit)
				if !ok {
					continue
				}
				found = true
				for _, elt := range cl.Elts {
					if id, ok := elt.(*ast.Ident); ok {
						names = append(names, id.Name)
					}
				}
			}
		}
	}

	if !found {
		fmt.Fprintln(os.Stderr, "allEventNames slice not found")
		os.Exit(2)
	}
	if len(names) == 0 {
		fmt.Fprintln(os.Stderr, "allEventNames is empty")
		os.Exit(2)
	}

	seen := map[string]bool{}
	for _, n := range names {
		val, ok := consts[n]
		if !ok {
			fmt.Fprintf(os.Stderr, "cannot resolve event constant %s\n", n)
			os.Exit(2)
		}
		if !seen[val] {
			seen[val] = true
			fmt.Println(val)
		}
	}
}
