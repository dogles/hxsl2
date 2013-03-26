/*
 * format - haXe File Formats
 *
 * Copyright (c) 2008, The haXe Project Contributors
 * All rights reserved.
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *
 *   - Redistributions of source code must retain the above copyright
 *     notice, this list of conditions and the following disclaimer.
 *   - Redistributions in binary form must reproduce the above copyright
 *     notice, this list of conditions and the following disclaimer in the
 *     documentation and/or other materials provided with the distribution.
 *
 * THIS SOFTWARE IS PROVIDED BY THE HAXE PROJECT CONTRIBUTORS "AS IS" AND ANY
 * EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 * WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 * DISCLAIMED. IN NO EVENT SHALL THE HAXE PROJECT CONTRIBUTORS BE LIABLE FOR
 * ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
 * SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
 * CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH
 * DAMAGE.
 */
package format.hxsl;

#if macro
import haxe.macro.Expr;
import haxe.macro.Context;
import format.agal.Data.RegType;
import format.hxsl.Data;
#end

class Build {
	macro public static function shader() : Array<Field> {
		var cl = Context.getLocalClass().get();
		var fields = Context.getBuildFields();
		var shader = null;
		var debug = false;
		for( m in cl.meta.get() )
			if( m.name == ":shader" ) {
				if( m.params.length != 1 )
					Context.error("@:shader metadata should only have one parameter", m.pos);
				shader = m.params[0];
				break;
			}
		if( shader == null ) {
			for( f in fields )
				if( f.name == "SRC" ) {
					switch( f.kind ) {
					case FVar(_, e):
						if( e != null ) {
							shader = e;
							fields.remove(f);
							haxe.macro.Compiler.removeField(Context.getLocalClass().toString(), "SRC", true);
							break;
						}
					default:
					}
				}
		}
		if( shader == null )
			Context.error("Missing SRC shader", cl.pos);

		for ( f in fields ) {
			if ( f.name == "DEBUG" ) {
				debug = true;
				break;
			}
		}

		var p = new Parser();
		p.includeFile = function(file) {
			var f = Context.resolvePath(file);
			return Context.parse("{"+neko.io.File.getContent(f)+"}", Context.makePosition( { min : 0, max : 0, file : f } ));
		};
		var v = try p.parse(shader) catch( e : Error ) haxe.macro.Context.error(e.message, e.pos);
		var c = new Compiler();
		c.warn = Context.warning;
		var serialized = try c.compile(v) catch( e : Error ) haxe.macro.Context.error(e.message, e.pos);

		var decls = [
			"override function getData() return '"+serialized+"'",
		];
		var e = Context.parse("{ var x : {" + decls.join("\n") + "}; }", shader.pos);
		var fdecls = switch( e.expr ) {
			case EBlock(el):
				switch( el[0].expr ) {
				case EVars(vl):
					switch( vl[0].type) {
					case TAnonymous(fl): fl;
					default: null;
					}
				default: null;
				}
			default: null;
		};
		if( fdecls == null ) throw "assert";

		return fields.concat(fdecls);
	}
}
