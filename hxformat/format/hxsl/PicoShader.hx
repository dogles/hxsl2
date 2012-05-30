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

#if flash
	private typedef TypeMap = flash.utils.TypedDictionary<String, VarType>;
#else
	private typedef TypeMap = Hash<VarType>;
#end

/** Simple shader builder that simply exports information about the shader. */
@:autoBuild(format.hxsl.Build.shader()) class PicoShader {
	public var idata:Data;

	/** Name to type map for compile vars */
	public var compileVarInfo : TypeMap;
	/** Name to type map for input vars */
	public var inputVarInfo : TypeMap;
	/** Name to type map for vertex uniform constants */
	public var vertexConstantInfo : TypeMap;
	/** Name to type map for fragment uniform constants */
	public var fragmentConstantInfo : TypeMap;
	/** Name to type map for textures */
	public var textureInfo : TypeMap;

	public function new() {
		this.idata = Serialize.unserialize(getData());

		compileVarInfo = createTypeMap(this.idata.compileVars);
		inputVarInfo = createTypeMap(this.idata.input);
		vertexConstantInfo = createTypeMap(this.idata.vertex.args);
		fragmentConstantInfo = createTypeMap(this.idata.fragment.args);
		textureInfo = createTypeMap(this.idata.fragment.tex);
	}

	function createTypeMap(ar:Iterable<Variable>) : TypeMap {
		var out = new TypeMap();
		for ( c in ar ) {
			out.set(c.name, c.type);
		}
		return out;
	}

	public function createInstance(compileVars:Dynamic=null) : ShaderInstance {
		return new ShaderInstance(this, new RuntimeCompiler().compile(idata, compileVars));
	}

	function getData() : String {
		throw "needs subclass";
		return null;
	}
}
