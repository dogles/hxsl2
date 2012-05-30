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
	private typedef NameMap = flash.utils.TypedDictionary<String, Int>;
#else
	private typedef NameMap = Hash<Int>;
#end

enum ProgramType { Vertex; Fragment; }

/**
 *  Represents a shader, compiled to the platform-specific format.
 *  Simply provides the compiled code and reflection info.
 */
class ShaderInstance
{
	public function new(shader:PicoShader, data:Data) {
		var c = new format.agal.Compiler();
		var vscode = c.compile(data.vertex);
		var fscode = c.compile(data.fragment);

		var max = 200;
		if( vscode.code.length > max )
			throw "This vertex shader uses " + vscode.code.length + " opcodes but only " + max + " are allowed by Flash11";
		if( fscode.code.length > max )
			throw "This fragment shader uses " + fscode.code.length + " opcodes but only " + max + " are allowed by Flash11";

		#if (debug && shaderDebug)
		trace("VERTEX");
		for( o in vscode.code )
			trace(format.agal.Tools.opStr(o));
		trace("FRAGMENT");
		for( o in fscode.code )
			trace(format.agal.Tools.opStr(o));
		#end

		var vsbytes = new haxe.io.BytesOutput();
		new format.agal.Writer(vsbytes).write(vscode);
		var fsbytes = new haxe.io.BytesOutput();
		new format.agal.Writer(fsbytes).write(fscode);

		this.vertexCode = vsbytes.getBytes().getData();
		this.fragmentCode = fsbytes.getBytes().getData();

		this.vertexLiterals = data.vertex.consts;
		this.fragmentLiterals = data.fragment.consts;

		this.inputRegisters = new NameMap();
		for ( input in data.input ) {
			this.inputRegisters.set(input.name, input.index);
		}

		this.vertexLiteralStart = 0;
		this.vertexParamRegisters = new NameMap();
		for ( arg in data.vertex.args ) {
			this.vertexParamRegisters.set(arg.name, arg.index);
			this.vertexLiteralStart = arg.index + Data.Tools.regSize(arg.type);
		}

		this.fragmentLiteralStart = 0;
		this.fragmentParamRegisters = new NameMap();
		for ( arg in data.fragment.args ) {
			this.fragmentParamRegisters.set(arg.name, arg.index);
			this.fragmentLiteralStart = arg.index + Data.Tools.regSize(arg.type);
		}

		this.textureRegisters = new NameMap();
		for ( tex in data.fragment.tex ) {
			this.textureRegisters.set(tex.name, tex.index);
		}
	}

	/** The shader this instance was created from */
	public var shader : PicoShader;
	/** Platform-specific vertex code */
	public var vertexCode : Dynamic;
	/** Platform-specific fragment code */
	public var fragmentCode : Dynamic;
	/** Map input name to register */
	public var inputRegisters:NameMap;
	/** Map vertex shader parameter name to register */
	public var vertexParamRegisters:NameMap;
	/** Map fragment shader parameter name to register */
	public var fragmentParamRegisters:NameMap;
	/** Map texture name to register */
	public var textureRegisters:NameMap;
	/** Literals to apply to vertex shader */
	public var vertexLiterals:Array<Array<Float>>; 
	/** Literals to apply to fragment shader */
	public var fragmentLiterals:Array<Array<Float>>; 
	/** Register that vertex shader literals should be uploaded to */
	public var vertexLiteralStart:Int; 
	/** Register that fragment shader literals should be uploaded to */
	public var fragmentLiteralStart:Int; 
}
