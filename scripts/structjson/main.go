// structjson extracts the JSON field surface of a named Go struct type
// using the official Go parser (go/ast) — no hand-rolled source parsing.
//
// Usage:
//
//	structjson <StructName> <file.go>...
//
// For the first definition of StructName found across the given files it
// prints one line per JSON-serialized field:
//
//	<json-name>\trequired|optional
//
// Rules:
//   - fields without a json tag, with `json:"-"`, or with an empty json
//     name are skipped (they are not part of the JSON surface);
//   - embedded (anonymous) fields are skipped;
//   - a field is "required" when its json tag carries no omitempty option
//     (the ecosystem convention: such fields are always serialized), and
//     "optional" otherwise.
//
// Exit codes: 0 = struct found and printed; 2 = usage error or struct not
// found (never a silent empty result).
package main

import (
	"fmt"
	"go/ast"
	"go/parser"
	"go/token"
	"os"
	"reflect"
	"sort"
	"strings"
)

func main() {
	if len(os.Args) < 3 {
		fmt.Fprintln(os.Stderr, "usage: structjson <StructName> <file.go>...")
		os.Exit(2)
	}
	name := os.Args[1]

	type field struct {
		name string
		req  string
	}
	var fields []field
	found := false

	fset := token.NewFileSet()
	for _, path := range os.Args[2:] {
		f, err := parser.ParseFile(fset, path, nil, 0)
		if err != nil {
			fmt.Fprintf(os.Stderr, "parse error: %s: %v\n", path, err)
			os.Exit(2)
		}
		ast.Inspect(f, func(n ast.Node) bool {
			if found {
				return false
			}
			ts, ok := n.(*ast.TypeSpec)
			if !ok || ts.Name.Name != name {
				return true
			}
			st, ok := ts.Type.(*ast.StructType)
			if !ok {
				return true
			}
			found = true
			for _, fl := range st.Fields.List {
				if len(fl.Names) == 0 { // embedded field
					continue
				}
				if fl.Tag == nil {
					continue
				}
				jt := reflect.StructTag(strings.Trim(fl.Tag.Value, "`")).Get("json")
				if jt == "" || jt == "-" {
					continue
				}
				parts := strings.Split(jt, ",")
				fname := parts[0]
				if fname == "" || fname == "-" {
					continue
				}
				req := "required"
				for _, opt := range parts[1:] {
					if opt == "omitempty" {
						req = "optional"
						break
					}
				}
				fields = append(fields, field{name: fname, req: req})
			}
			return false
		})
		if found {
			break
		}
	}

	if !found {
		fmt.Fprintf(os.Stderr, "struct %s not found in the given files\n", name)
		os.Exit(2)
	}

	sort.Slice(fields, func(i, j int) bool { return fields[i].name < fields[j].name })
	for _, fl := range fields {
		fmt.Printf("%s\t%s\n", fl.name, fl.req)
	}
}
