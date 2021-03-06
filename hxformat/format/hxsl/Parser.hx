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

import format.hxsl.Data;
import haxe.macro.Expr;
import haxe.macro.Context;

class Parser {

	var vertex : Function;
	var fragment : Function;
	var helpers : Hash<Function>;
	var vars : Array<ParsedVar>;
	var cur : ParsedCode;
	var allowReturn : Bool;
	var inConditional : Bool;

	public function new() {
		helpers = new Hash();
		vars = [];
	}

	function error(msg:String, p:Position) : Dynamic {
		throw new Error(msg, p);
		return null;
	}

	public function parse( e : Expr ) : ParsedHxsl {
		switch( e.expr ) {
		case EBlock(l):
			for( x in l )
				parseDecl(x);
		default:
			error("Shader code should be a block", e.pos);
		}
		if( vertex == null ) error("Missing vertex function", e.pos);
		if( fragment == null ) error("Missing fragment function", e.pos);
		if( !hasInputs() ) error("Missing input variable", e.pos);
		allowReturn = false;
		var vs = buildShader(vertex);
		var fs = buildShader(fragment);
		var help = new Hash();
		allowReturn = true;
		for( h in helpers.keys() )
			help.set(h, buildShader(helpers.get(h)));
		return { vertex : vs, fragment : fs, vars : vars, pos : e.pos, helpers : help };
	}

	function hasInputs() {
		for ( v in vars ) {
			switch(v.k) {
			case VInput:
				return true;
			default:
			}
		}
		return false;
	}

	public dynamic function includeFile( file : String ) : Null<Expr> {
		return null;
	}

	function getType( t : ComplexType, pos ) {
		switch(t) {
		case TPath(p):
			if( p.params.length == 1 ) {
				switch( p.params[0] ) {
				case TPExpr(e):
					switch( e.expr ) {
					case EConst(c):
						switch( c ) {
						case CInt(i):
							p.params = [];
							var i = Std.parseInt(i);
							if( i > 0 )
								return TArray(getType(t,pos), i);
						default:
						}
					default:
					}
				default:
				}
			}
			if( p.pack.length > 0 || p.sub != null || p.params.length > 0 )
				error("Unsupported type", pos);
			return switch( p.name ) {
			case "Bool": TBool;
			case "Float": TFloat;
			case "Float2": TFloat2;
			case "Float3": TFloat3;
			case "Float4": TFloat4;
			case "Matrix", "M44": TMatrix(4, 4, { t : null } );
			case "M33": TMatrix(3, 3, { t : null } );
			case "M34": TMatrix(3, 4, { t : null } );
			case "M43": TMatrix(4, 3, { t : null } );
			case "Texture": TTexture(false);
			case "CubeTexture": TTexture(true);
			case "Color", "Int": TInt;
			default:
				error("Unknown type '" + p.name + "'", pos);
			}
		default:
			error("Unsupported type", pos);
		}
		return null;
	}

	function allocVarDecl( v, t, p ) : ParsedVar {
		if ( t != null ) switch (t ) {
		case TPath(path):
			if ( path.params.length == 1 ) {
				switch (path.params[0]) {
				case TPType(tt):
					var alloced = allocVar(v, tt, getKindFromName(path.name, p), p);
					// Texture types can only specify uniform kind
					switch ( alloced.t ) {
					case TTexture(_):
						if ( alloced.k != VGlobalParam ) {
							error("Invalid kind for texture: " + v, p);
						}
						alloced.k = VGlobalTexture;
					default:
					}
					return alloced;
				default:
				}
			}
		default:
		}

		// leave kind indeterminate until it is used.
		return allocVar(v, t, null, p);
	}

	function allocVar( v, t, k, p ) : ParsedVar {
		return { n : v, k : k, t : t == null ? null : getType(t, p), p : p };
	}

	function getKindFromName( name:String, p ) {
		switch ( name ) {
		case "Input": return VInput;
		case "Varying": return VVar;
		case "Param": return VGlobalParam;
		case "Constant":return VCompileConstant;
		default:
			error("Unrecognized kind: " + name, p);
			return null;
		}
	}

	function parseDecl( e : Expr ) {
		switch( e.expr ) {
		case EVars(vl):
			var p = e.pos;
			for( v in vl ) {
				if( v.type == null ) error("Missing type for variable '" + v.name + "'", e.pos);
				if( v.name == "input" ) {
					switch( v.type ) {
					case TAnonymous(fl):
						for( f in fl )
							switch( f.kind ) {
							case FVar(t,_): vars.push(allocVar(f.name,t,VInput,p));
							default: error("Invalid input variable type", e.pos);
							}
					default: error("Invalid type for shader input : should be anonymous", e.pos);
					}
				} else {
					vars.push(allocVarDecl(v.name, v.type, p));
				}
			}
			return;
		case EFunction(name,f):
			switch( name ) {
			case "vertex": vertex = f;
			case "fragment": fragment = f;
			default:
				if( helpers.exists(name) )
					error("Duplicate function '" + name + "'", e.pos);
				helpers.set(name, f);
			}
			return;
		case ECall(f, pl):
			switch( f.expr ) {
			case EConst(c):
				switch( c ) {
				case CIdent(s):
					if( s == "include" && pl.length == 1 ) {
						switch( pl[0].expr ) {
						case EConst(c):
							switch( c ) {
							case CString(str):
								var f = includeFile(str);
								if( f == null )
									error("Failed to include file", pl[0].pos);
								switch( f.expr ) {
								case EBlock(el):
									for( e in el )
										parseDecl(e);
								default:
									parseDecl(f);
								}
								return;
							default:
							}
						default:
						}
					}
				default:
				}
			default:
			}
		default:
		};
		error("Unsupported declaration", e.pos);
	}

	function buildShader( f : Function ) {
		cur = {
			pos : f.expr.pos,
			args : [],
			exprs : [],
		};
		var pos = f.expr.pos;
		for( p in f.args ) {
			if( p.type == null ) error("Missing parameter type '" + p.name + "'", pos);
			if( p.value != null ) error("Unsupported default value", p.value.pos);
			cur.args.push(allocVar(p.name, p.type, VParam, pos));
		}
		parseExpr(f.expr);
		return cur;
	}


	function addAssign( e1 : ParsedValue, e2 : ParsedValue, p : Position ) {
		cur.exprs.push( { v : e1, e : e2, p : p } );
	}

	function parseExpr( e : Expr ) {
		switch( e.expr ) {
		case EBlock(el):
			var eold = cur.exprs;
			var old = allowReturn;
			var last = el[el.length - 1];
			cur.exprs = [];
			for( e in el ) {
				allowReturn = old && (e == last);
				parseExpr(e);
			}
			allowReturn = old;
			eold.push({ v : null, e : { v : PBlock(cur.exprs), p : e.pos }, p : e.pos });
			cur.exprs = eold;
		case EIf(cond, eif, eelse):
			if ( inConditional ) throw "assert";
			inConditional = true;
			var pcond = parseValue(cond);
			inConditional = false;

			var eold = cur.exprs;
			cur.exprs = [];
			parseExpr(eif);
			var pif = cur.exprs;
			cur.exprs = eold;

			var pelse = null;
			if ( eelse != null ) {
				cur.exprs = [];
				parseExpr(eelse);
				pelse = cur.exprs;
				cur.exprs = eold;
			}

			cur.exprs.push( {v:null, e: { v:PIf(pcond, pif, pelse), p : e.pos }, p : e.pos} );
		case EBinop(op, e1, e2):
			switch( op ) {
			case OpAssign:
				addAssign(parseValue(e1), parseValue(e2), e.pos);
			case OpAssignOp(op):
				addAssign(parseValue(e1), parseValue( { expr : EBinop(op, e1, e2), pos : e.pos } ), e.pos);
			default:
				error("Operation should have side-effects", e.pos);
			}
		case EVars(vl):
			for( v in vl ) {
				if( v.expr == null && v.type == null )
					error("Missing type for variable '" + v.name + "'", e.pos);
				var l = { v : PLocal(allocVar(v.name, v.type, VTmp, e.pos)), p : e.pos };
				cur.exprs.push( { v : l, e : v.expr == null ? null : parseValue(v.expr), p : e.pos } );
			}
		case ECall(v, params):
			switch( v.expr ) {
			case EConst(c):
				switch(c) {
				case CIdent(s):
					if( s == "kill" && params.length == 1 ) {
						var v = parseValue(params[0]);
						cur.exprs.push( { v : null, e : { v : PUnop(CKill,v), p : e.pos }, p : e.pos } );
						return;
					}
				default:
				}
			default:
			}
			error("Unsupported call", e.pos);
		case EFor(it, expr):
			var min = null, max = null, vname = null;
			switch( it.expr ) {
			case EIn(v,it):
				switch( v.expr ) {
				case EConst(c):
					switch( c ) {
					case CIdent(i), CType(i): vname = i;
					default:
					}
				default:
				}
				switch( it.expr ) {
				case EBinop(op, e1, e2):
					if( op == OpInterval ) {
						min = parseValue(e1);
						max = parseValue(e2);
					}
				default:
				}
			default:
			}
			if( min == null || max == null || vname == null ) {
				error("For iterator should be in the form x...y", it.pos);
			}

			var len = cur.exprs.length;
			parseExpr(expr);
			if ( cur.exprs.length != len+1 ) throw "assert";
			var itvar = {n:vname, t:TFloat, k:VTmp, p:it.pos};
			cur.exprs.push( {v : null, e:{v:PFor(itvar, min, max, cur.exprs.pop()), p:e.pos}, p:e.pos } );
		case EReturn(r):
			if( r == null ) error("Return must return a value", e.pos);
			if( !allowReturn ) error("Return only allowed as final expression in helper methods", e.pos);
			var v = parseValue(r);
			cur.exprs.push( { v : null, e : { v : PReturn(v), p : e.pos }, p : e.pos } );
		default:
			error("Unsupported expression", e.pos);
		}
	}

	function parseValue( e : Expr ) : ParsedValue {
		switch( e.expr ) {
		case EField(ef, s):
			var v = parseValue(ef);
			var chars = "xrygzbwa";
			var swiz = [];
			for( i in 0...s.length )
				switch( chars.indexOf(s.charAt(i)) ) {
				case 0,1: swiz.push(X);
				case 2,3: swiz.push(Y);
				case 4,5: swiz.push(Z);
				case 6,7: swiz.push(W);
				default: error("Unknown field " + s, e.pos);
				}
			return { v : PSwiz(v,swiz), p : e.pos };
		case EConst(c):
			switch( c ) {
			case CType(i), CIdent(i):
				if ( i == "null" || i == "true" || i == "false" ) {
					return { v : PConst(i), p : e.pos };
				} else {
					return { v : PVar(i), p : e.pos };
				}
			case CInt(v):
				return { v : PConst(v), p : e.pos };
			case CFloat(f):
				return { v : PConst(f), p : e.pos };
			default:
			}
		case EBinop(op, e1, e2):
			var op = switch( op ) {
			case OpMult: "mul";
			case OpAdd: "add";
			case OpDiv: "div";
			case OpSub: "sub";
			case OpLt: "lt";
			case OpLte: "lte";
			case OpGt: "gt";
			case OpEq: "eq";
			case OpNotEq: "neq";
			case OpGte: "gte";
			case OpMod: "mod";
			case OpBoolOr: "or";
			case OpBoolAnd: "and";
			default: error("Unsupported operation", e.pos);
			};
			return makeCall(op, [e1, e2], e.pos);
		case EUnop(op, _, e1):
			var op = switch( op ) {
			case OpNeg: "neg";
			case OpNot: "not";
			default: error("Unsupported operation", e.pos);
			}
			return makeCall(op, [e1], e.pos);
		case ECall(c, params):
			switch( c.expr ) {
			case EField(v, f):
				return makeCall(f, [v].concat(params), e.pos);
			case EConst(c):
				switch( c ) {
				case CIdent(i), CType(i):
					return makeCall(i, params, e.pos);
				default:
				}
			default:
			}
		case EArrayDecl(values):
			var vl = [];
			for( v in values )
				vl.push(parseValue(v));
			return { v : PVector(vl), p : e.pos };
		case EParenthesis(k):
			var v = parseValue(k);
			v.p = e.pos;
			return v;
		case EIf(ec, eif, eelse), ETernary(ec,eif,eelse):
			var vcond = parseValue(ec);
			var vif = parseValue(eif);
			if( eelse == null ) error("'if' needs an 'else'", e.pos);
			var velse = parseValue(eelse);
			return { v : PIff(vcond, vif, velse), p : e.pos };
		case EArray(e1, e2):
			var e1 = parseValue(e1);
			var e2 = parseValue(e2);
			switch(e2.v) {
			case PConst(v):
				var i = Std.parseInt(v);
				if( Std.string(i) == v )
					return { v : PRow(e1, i), p : e.pos };
			default:
				switch(e1.v) {
				case PVar(v):
					return { v : PAccess(v, e2), p : e.pos };
				default:
				}
			}
			error("Matrix row needs to be a constant integer", e2.p);
		default:
		}
		error("Unsupported value expression", e.pos);
		return null;
	}

	function parseInt( e : Expr ) : Null<Int> {
		return switch( e.expr ) {
		case EConst(c): switch( c ) { case CInt(i): Std.parseInt(i); default: null; }
		case EUnop(op, _, e):
			if( op == OpNeg ) {
				var i = parseInt(e);
				if( i == null ) null else -i;
			} else
				null;
		default: null;
		}
	}

	function replaceVar( v : String, by : ExprDef, e : Expr ) {
		return { expr : switch( e.expr ) {
		case EConst(c):
			switch( c ) {
			case CIdent(v2):
				if( v == v2 ) by else e.expr;
			default:
				e.expr;
			}
		case EBinop(op, e1, e2):
			EBinop(op, replaceVar(v, by, e1), replaceVar(v, by, e2));
		case EUnop(op, p, e):
			EUnop(op, p, replaceVar(v, by, e));
		case EVars(vl):
			var vl2 = [];
			for( x in vl )
				vl2.push( { name : x.name, type : x.type, expr : if( x.expr == null ) null else replaceVar(v, by, x.expr) } );
			EVars(vl2);
		case ECall(e, el):
			ECall(replaceVar(v, by, e), Lambda.array(Lambda.map(el, callback(replaceVar, v, by))));
		case EFor(it, e):
			EFor(replaceVar(v, by, it), replaceVar(v, by, e));
		case EBlock(el):
			EBlock(Lambda.array(Lambda.map(el, callback(replaceVar, v, by))));
		case EArrayDecl(el):
			EArrayDecl(Lambda.array(Lambda.map(el, callback(replaceVar, v, by))));
		case EIf(cond, eif, eelse), ETernary(cond,eif,eelse):
			EIf(replaceVar(v, by, cond), replaceVar(v, by, eif), eelse == null ? null : replaceVar(v, by, eelse));
		case EField(e, f):
			EField(replaceVar(v, by, e), f);
		case EParenthesis(e):
			EParenthesis(replaceVar(v, by, e));
		case EType(e, f):
			EType(replaceVar(v, by, e), f);
		case EArray(e1, e2):
			EArray(replaceVar(v, by, e1), replaceVar(v, by, e2));
		case EIn(a,b):
			EIn(replaceVar(v,by,a),replaceVar(v,by,b));
		case EWhile(_), EUntyped(_), ETry(_), EThrow(_), ESwitch(_), EReturn(_), EObjectDecl(_), ENew(_), EFunction(_), EDisplay(_), EDisplayNew(_), EContinue, ECast(_), EBreak:
			e.expr;
		/*
		case ECheckType(e,t):
			ECheckType(replaceVar(v, by, e),t);
		*/
		}, pos : e.pos };
	}

	inline function makeUnop( op, e, p ) {
		return { v : PUnop(op, e), p : p };
	}

	inline function makeOp( op, e1, e2, p ) {
		return { v : POp(op, e1, e2), p : p };
	}

	function checkTextureFlagDups(flags:Array<ParsedExpr>) {
		var hasMip = false;
		var hasWrap = false;
		var hasFilter = false;
		var hasSingle = false;
		var hasLodBias = false;
		for ( expr in flags ) {
			if ( expr.v == null ) {
				switch ( expr.e.v ) {
				case PConst(s):
					switch ( s ) {
					case "mm_no", "mm_near", "mm_linear": 
						if ( hasMip ) {
							error("Duplicate or conflicting mipmap flag: " + s, expr.p);
						}
						hasMip = true;
					case "wrap", "clamp":
						if ( hasWrap ) {
							error("Duplicate or conflicting wrap/clamp flag: " + s, expr.p);
						}
						hasWrap = true;
					case "nearest", "linear":
						if ( hasFilter ) {
							error("Duplicate or conflicting filter flag: " + s, expr.p);
						}
						hasFilter = true;
					case "single":
						if ( hasSingle ) {
							error("Duplicate or conflicting single flag: " + s, expr.p);
						}
						hasSingle = true;
					default: throw "assert";
					}
				default: throw "assert";
				}
			} else {
				switch ( expr.v.v ) {
				case PConst(s):
					switch (s) {
					case "lod":
						if ( hasLodBias ) {
							error("Duplicate or conflicting lod flag: " + s, expr.p);
						}
						hasLodBias = true;
					case "mipmap":
						if ( hasMip ) {
							error("Duplicate or conflicting mipmap flag: " + s, expr.p);
						}
						hasMip = true;
					case "wrap", "clamp":
						if ( hasWrap ) {
							error("Duplicate or conflicting wrap/clamp flag: " + s, expr.p);
						}
						hasWrap = true;
					case "filter":
						if ( hasFilter ) {
							error("Duplicate or conflicting filter flag: " + s, expr.p);
						}
						hasFilter = true;
					case "single":
						if ( hasSingle ) {
							error("Duplicate or conflicting single flag: " + s, expr.p);
						}
						hasSingle = true;
					default: throw "assert";
					}
				default: throw "assert";
				}
			}
		}
	}

	function makeCall( n : String, params : Array<Expr>, p : Position ) {

		if( helpers.exists(n) ) {
			var vl = [];
			for( p in params )
				vl.push(parseValue(p));
			return { v : PCall(n, vl), p : p };
		}

		// texture handling
		if( n == "get" && params.length >= 2 ) {
			var v = parseValue(params.shift());
			var v = switch( v.v ) {
			case PVar(v): v;
			default: error("get should only be used on a single texture variable", v.p);
			};
			var t = parseValue(params.shift());
			var flags = [];
			var idents = ["mm_no","mm_near","mm_linear","wrap","clamp","nearest","linear","single","lod(x)"];
			var values = [TMipMapDisable,TMipMapNearest,TMipMapLinear,TWrap,TClamp,TFilterNearest,TFilterLinear,TSingle];
			var targets = ["mipmap", "wrap", "clamp", "filter", "lod"];
			var targetValues = [PMipMap, PWrap, PClamp, PFilter, PLodBias];
			for( p in params ) {
				switch( p.expr ) {
				case EBinop(op, e1, e2):
					switch ( op ) {
					case OpAssign:
						switch (e1.expr) {
						case EConst(c):
							switch (c) {
							case CIdent(sflag):
								var ip = Lambda.indexOf(targets, sflag);
								if ( ip >= 0 ) {
									flags.push( {v:{v:PConst(sflag), p:e1.pos}, e:parseValue(e2), p:p.pos} );
									continue;
								}
								error("Invalid parameter, should be "+targets.join("|"), p.pos);
							default:
							}
						default: error("Invalid syntax for texture get", p.pos);
						}
					default: error("Invalid syntax for texture get", p.pos);
					}
				case EConst(c):
					switch( c ) {
					case CIdent(sflag):
						var ip = Lambda.indexOf(idents, sflag);
						if( ip >= 0 ) {
							flags.push( {v:null, e:{v:PConst(sflag), p:p.pos}, p:p.pos} );
							continue;
						}
					default:
					}
				case ECall(c,pl):
					switch( c.expr ) {
					case EConst(c):
						switch( c ) {
						case CIdent(v):
							if( v == "lod" && pl.length == 1 ) {
								switch( pl[0].expr ) {
								case EConst(c):
									switch( c ) {
									case CInt(v), CFloat(v):
										flags.push( { v : {v : PConst("lod"), p : p.pos}, e : parseValue(pl[0]), p : p.pos } );
										continue;
									default:
									}
								default:
								}
							}
						default:
						}
					default:
					}
				default:
				}
				error("Invalid parameter, should be "+idents.join("|"), p.pos);
			}

			checkTextureFlagDups(flags);
			return { v : PTex(v, t, flags), p : p };
		}
		// build operation
		var v = [];
		for( p in params )
			v.push(parseValue(p));
		var me = this;
		function checkParams(k) {
			if( params.length < k ) me.error(n + " require " + k + " parameters", p);
		}
		switch(n) {
		case "get": checkParams(2); // will cause an error

		case "inv","rcp": checkParams(1); return makeUnop(CRcp, v[0], p);
		case "sqt", "sqrt": checkParams(1); return makeUnop(CSqrt, v[0], p);
		case "rsq", "rsqrt": checkParams(1); return makeUnop(CRsq, v[0], p);
		case "log": checkParams(1); return makeUnop(CLog, v[0], p);
		case "exp": checkParams(1); return makeUnop(CExp, v[0], p);
		case "len", "length": checkParams(1); return makeUnop(CLen, v[0], p);
		case "sin": checkParams(1); return makeUnop(CSin, v[0], p);
		case "cos": checkParams(1); return makeUnop(CCos, v[0], p);
		case "abs": checkParams(1); return makeUnop(CAbs, v[0], p);
		case "neg": checkParams(1); return makeUnop(CNeg, v[0], p);
		case "sat", "saturate": checkParams(1); return makeUnop(CSat, v[0], p);
		case "frc", "frac": checkParams(1); return makeUnop(CFrac, v[0], p);
		case "int": checkParams(1);  return makeUnop(CInt,v[0], p);
		case "nrm", "norm", "normalize": checkParams(1); return makeUnop(CNorm, v[0], p);
		case "trans", "transpose": checkParams(1); return makeUnop(CTrans, v[0], p);

		case "add": checkParams(2); return makeOp(CAdd, v[0], v[1], p);
		case "sub": checkParams(2); return makeOp(CSub, v[0], v[1], p);
		case "mul": checkParams(2); return makeOp(CMul, v[0], v[1], p);
		case "div": checkParams(2); return makeOp(CDiv, v[0], v[1], p);
		case "pow": checkParams(2); return makeOp(CPow, v[0], v[1], p);
		case "min": checkParams(2); return makeOp(CMin, v[0], v[1], p);
		case "max": checkParams(2); return makeOp(CMax, v[0], v[1], p);
		case "mod": checkParams(2); return makeOp(CMod, v[0], v[1], p);
		case "dp","dp3","dp4","dot": checkParams(2); return makeOp(CDot, v[0], v[1], p);
		case "crs", "cross": checkParams(2); return makeOp(CCross, v[0], v[1], p);

		case "lt", "slt": checkParams(2); return makeOp(CLt, v[0], v[1], p);
		case "gte", "sge": checkParams(2); return makeOp(CGte, v[0], v[1], p);
		case "gt", "sgt": checkParams(2); return makeOp(CLt, v[1], v[0], p);
		case "lte", "sle": checkParams(2); return makeOp(CGte, v[1], v[0], p);
		case "eq", "seq": checkParams(2); return makeOp(CEq, v[1], v[0], p);
		case "neq", "sne": checkParams(2); return makeOp(CNeq, v[1], v[0], p);
		case "or": checkParams(2); return makeOp(COr, v[0], v[1], p);
		case "and": checkParams(2); return makeOp(CAnd, v[0], v[1], p);
		case "not": checkParams(1); return makeUnop(CNot, v[0], p);
		default:
		}
		return error("Unknown operation '" + n + "'", p);
	}

}
