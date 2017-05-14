import std.file;
import std.stdio;
import std.string;
import std.algorithm;
import std.range;

void portFile(string filename) {
	// For better debuggability, we read the entire file into memory once,
	// then look at it and mutate it a bunch of times, then write it back.
	string contents = readText(filename);

	contents = fixBoxApi(contents);
	contents = removeBorderWidth(contents);
	contents = fixGtkInit(contents);
	contents = fixCssProvider(contents);
	contents = fixShowAll(contents);
	contents = fixNoShowAll(contents);
	contents = fixMisc(contents);
	contents = fixButtonApi(contents);
	contents = fixExpanderApi(contents);

	// Write result back
	std.file.write(filename, contents);
}

string fixExpanderApi(string input) {
	string buffer;

	foreach (line; input.lineSplitter) {
		size_t index = line.indexOf("gtk_expander_set_spacing");

		if (index == -1) {
			buffer ~= line ~ "\n";
			continue;
		}
	}

	return buffer;

}

string removeBorderWidth(string input) {
	string buffer;

	foreach (line; input.lineSplitter) {
		size_t index = line.indexOf("gtk_container_set_border_width");

		if (index == -1) {
			buffer ~= line ~ "\n";
			continue;
		}

		// The "fix" for this is to not use it.
	}

	return buffer;
}

string fixGtkInit(string input) {
	string buffer;

	foreach (line; input.lineSplitter) {
		import std.ascii: isWhite;
		size_t index = line.indexOf("gtk_init");

		if (index == -1) {
			buffer ~= line ~ "\n";
			continue;
		}

		// fix by removing the parameters entirely
		auto openParenIndex = line.indexOf('(');

		if (openParenIndex == -1 ||
		    (index > 0 && !line[index - 1].isWhite())) {
			// Huh?
			buffer ~= line ~ "\n";
			continue;
		}

		buffer ~= line[0..openParenIndex + 1];
		buffer ~= ");\n";
	}

	return buffer;
}
unittest {
	assert(fixGtkInit("gtk_init (&argc, &argv);") == "gtk_init ();\n");
	assert(fixGtkInit("dialog_gtk_init (foo);") == "dialog_gtk_init (foo);\n");
}

string fixCssProvider(string input) {
	string buffer;

	foreach (line; input.lineSplitter) {
		auto nComma = 2;
		size_t index = line.indexOf("gtk_css_provider_load_from_data");

		if (index == -1) {
			index = line.indexOf("gtk_css_provider_load_from_file");
			if (index == -1) {
				index = line.indexOf("gtk_css_provider_load_from_path");
			}
		} else {
			nComma = 3;
		}

		if (index == -1) {
			buffer ~= line ~ "\n";
			continue;
		}

		// These 3 functions all lost their last argument, so remove it.
		auto openParenIndex = line.indexOf('(');
		if (openParenIndex == -1) {
			buffer ~= line ~ "\n";
			continue;
		}

		auto commaIndex = line.skipToNested(',', nComma, openParenIndex + 1);
		if (commaIndex == -1) {
			buffer ~= line ~ "\n";
			continue;
		}

		buffer ~= line[0..commaIndex];
		buffer ~= ");\n";
	}

	return buffer;
}
unittest {
	assert(fixCssProvider("gtk_css_provider_load_from_data (1, 2, 3, 4)") ==
	                      "gtk_css_provider_load_from_data (1, 2, 3);\n");
}


string fixBoxApi(string input) {
	string buffer;

	// TODO: Handle pack_{start, end} calls over multiple lines

	foreach (line; input.lineSplitter) {
		size_t index = line.indexOf("gtk_box_pack_start");
		if (index == -1)
			index = line.indexOf("gtk_box_pack_end");

		if (index == -1) {
			buffer ~= line ~ "\n";
			continue;
		}

		// Remove last 3 parameters
		// In other words, Everything after the second comma in the
		// gtk_box_ call. First the instance, then the child.
		size_t endIndex = skipToNested(line, ',', 2, line.indexOf('(') + 1);
		if (endIndex == cast(size_t)-1) {
			// No comma found. Already ported?
			buffer ~= line ~ "\n";
			continue;
		}
		buffer ~= line[0..endIndex];
		buffer ~= ");\n";
	}

	return buffer;
}
unittest {
	assert(fixBoxApi("  gtk_box_pack_start(a, b, c, d)") == "  gtk_box_pack_start(a, b);\n");
}


string fixShowAll(string input) {
	string buffer;

	foreach (line; input.lineSplitter) {
		size_t index = line.indexOf("gtk_widget_show_all");

		if (index == -1) {
			buffer ~= line ~ "\n";
			continue;
		}

		buffer ~= line[0..index];
		buffer ~= "gtk_widget_show";
		buffer ~= line[index + "gtk_widget_show_all".length..$];
		buffer ~= "\n";
	}
	return buffer;
}
unittest {
	assert(fixShowAll("abc gtk_widget_show_all (foo)") == "abc gtk_widget_show (foo)\n");
}

string fixNoShowAll(string input) {
	string buffer;

	foreach (line; input.lineSplitter) {
		size_t index = line.indexOf("gtk_widget_set_no_show_all");

		if (index == -1) {
			buffer ~= line ~ "\n";
			continue;
		}

		// The "fix" for this is to not use it.
	}

	return buffer;
}

string fixMisc(string input) {
	string buffer;

	foreach (line; input.lineSplitter) {
		size_t index = line.indexOf("gtk_misc_set_alignment");

		if (index == -1) {
			buffer ~= line ~ "\n";
			continue;
		}

		auto openParenIndex = line.indexOf('(');
		if (openParenIndex == -1) {
			buffer ~= line ~ "\n";
			continue;
		}
		// If the first param contains the word "label", we just assume
		// that it's a GtkLabel. If the used API then was _set_alignment,
		// we use gtk_label_set_{x,y}align instead.
		auto firstCommaIndex = line.skipToNested(',', 1, openParenIndex + 1);
		if (firstCommaIndex == -1) {
			buffer ~= line ~ "\n";
			continue;
		}
		string firstParam = line[openParenIndex + 1..firstCommaIndex];


		// TODO: it's hard to make this all resilient against non-conforming
		//       input since we are changing @buffer everywhere.

		if (firstParam.canFind("label")) {
			firstParam = firstParam.replace("GTK_MISC", "GTK_LABEL");
			// Replace with gtk_label_set_xalign and gtk_label_set_yalign.
			auto nonWhitespaceIndex = line.skipToNonWhitespace();
			string indentation = line[0..nonWhitespaceIndex];
			buffer ~= indentation ~ "gtk_label_set_xalign";
			buffer ~= line[nonWhitespaceIndex + "gtk_misc_set_alignment".length..openParenIndex];
			buffer ~= "(" ~ firstParam ~ ",";
			auto secondCommaIndex = line.skipToNested(',', 1, firstCommaIndex + 1);

			string secondParam = line[firstCommaIndex + 1..secondCommaIndex];
			buffer ~= secondParam ~ ");\n";

			buffer ~= indentation ~ "gtk_label_set_yalign";
			buffer ~= line[nonWhitespaceIndex + "gtk_misc_set_alignment".length..openParenIndex];
			buffer ~= "(";
			buffer ~= firstParam ~ ",";
			auto closeParenIndex = line.skipToNested(')', 1, secondCommaIndex + 1);
			string thirdParam = line[secondCommaIndex + 1..closeParenIndex];
			buffer ~= thirdParam ~ ");\n";
		} else {
			buffer ~= line ~ "\n";
			continue;
		}
	}

	return buffer;
}

unittest {
	assert(fixMisc("gtk_misc_set_alignment (zomg)") == "gtk_misc_set_alignment (zomg)\n");
	assert(fixMisc("\t  gtk_misc_set_alignment (label, 0.0, 1.0)") == "\t  gtk_label_set_xalign (label, 0.0);\n\t  gtk_label_set_yalign (label, 1.0);\n");
}

string fixButtonApi(string input) {
	string buffer;

	foreach (line; input.lineSplitter) {
		size_t index = line.indexOf("gtk_button_set_always_show_image");

		if (index == -1) {
			buffer ~= line ~ "\n";
			continue;
		}

		// The "fix" for this is to not use it.
	}

	//foreach (line; buffer.lineSplitter) {
		//size_t index = line.indexOf("gtk_button_set_image");

		//if (index == -1) {
			//buffer ~= line ~ "\n";
			//continue;
		//}
	//}

	//foreach (line; buffer.lineSplitter) {
		//size_t index = line.indexOf("gtk_expander_set_spacing");

		//if (index == -1) {
			//buffer ~= line ~ "\n";
			//continue;
		//}
	//}

	return buffer;
}

pure @nogc
size_t skipToNested(string line, char needle, int nOccurrences, size_t start = 0) {
	size_t index = start;

	assert(start < line.length);

	int parenLevel = 0;

	int occurrences = 0;
	for (auto i = start; i < line.length; i ++) {
		auto c = line[i];

		if (c == needle && parenLevel == 0) {
			occurrences ++;
			if (occurrences == nOccurrences)
				return i;
		}

		if (c == '(') {
			parenLevel ++;
		} else if (c == ')') {
			parenLevel --;
		}
	}
	return -1;
}
unittest {
	assert(skipToNested("foo(foo(a,b),c)", ',', 1) == cast(size_t)-1);
	assert(skipToNested("foo(foo(a,b),c)", ',', 1, 4) == 12);
	assert(skipToNested("a(b)c)", ')', 1) == 5);
}

pure @nogc
size_t skipToNonWhitespace(string line) {
	import std.ascii: isWhite;
	for (auto i = 0; i < line.length; i ++) {
		if (!line[i].isWhite()) {
			return i;
		}
	}
	return -1;
}
unittest {
	assert(skipToNonWhitespace("   b") == 3);
}




























































































struct Token {
	string text;
	size_t start;
	size_t end;
}

//pure @nogc
auto tokenize(string input) {
	pure @nogc
	bool splitsToken(const char c) {
		switch(c) {
		case '(':
		case ')':
		case ';':
		case '<':
		case '>':
		case ',':
		case '%':
		case '=':
		case '^':
		case ' ':
		case '\t':
		case '\n':
			return true;
		default:
			return false;
		}
	}

	struct Result {
		string input;
		size_t cur;
		size_t tok_len;
		bool _empty = false;

		//pure @nogc
		this(string i) {
			input = i;
			// @cur should always point to *after* the current token
			cur = 0;
			tok_len = 0;

			if (!empty)
				popFront(); // Read current token
		}

		//pure @nogc @property
		Token front() {
			return Token(input[cur-tok_len..cur], cur-tok_len, cur);
		}

		//pure @nogc @property
		bool empty() {
			return _empty;
		}

		//pure @nogc
		void popFront() {
			assert(!empty);
			import std.ascii: isWhite;
			size_t inc = 0;

			// Skip whitespace
			while(cur < input.length && input[cur].isWhite()) {
				cur ++;
			}

			if (cur >= input.length) {
				_empty = true;
				return;
			}

			if (splitsToken(input[cur])) {
				// This is not a full C tokenizer, so just handle every
				// splitting char as one token.
				cur ++;
				tok_len = 1;
				return;
			}

			do {
				inc ++;
			} while (cur + inc < input.length && !splitsToken(input[cur + inc]));
			tok_len = inc;
			cur+= inc;
		}
	}

	Result r;              // can define a range object
	if (r.empty) {}   // can test for empty
	r.popFront();     // can invoke popFront()
	auto h = r.front; // can get the front of the range of non-void type



	return Result(input);
}
unittest {
	auto toks = "".tokenize();
	assert(toks.empty);

	toks = "a;b".tokenize();
	assert(toks.front.text == "a");
	toks.popFront();
	assert(toks.front.text == ";");
	toks.popFront();
	assert(toks.front.text == "b");
	toks.popFront();
	assert(toks.empty());


	import std.array: array;
	toks = "a".tokenize();
	assert(!toks.empty);

	toks = "foobar 123 ;%^".tokenize();
	assert(toks.array().length == 5);
	//assert(toks.array() == ["foobar", "123", ";", "%", "^"]);

	toks = "foobar ();".tokenize();
	assert(toks.array.length == 4);
}




auto testRange(string input) {
	struct Result {
		int c = 0;

		@property
		bool empty(){ return c == 10; }
		@property
		auto front(){ return c; }
		void popFront() { c++; }
	}

	return Result();
}

void takeTestRange(R)(R range) {
	foreach (c; range)
		writeln(c);
}





void portFile2(string filename) {
	string contents = readText(filename);
	contents = contents.tokenize.removeFunctions();

	writeln("Output:\n", contents);
}





// Ideally these should return void...
const string[] functionsToRemove = [
	"gdk_window_process_updates",
];

string removeFunctions(R)(R tokens)
	if (isInputRange!R)
{
	while (!tokens.empty) {
		auto tok = tokens.front;
		// Here we handle different function calls and their replacements.
		int index = -1;
		for (int i = 0; i < functionsToRemove.length; i ++) {
			if (tok.text == functionsToRemove[i]) {
				index = i;
				break;
			}
		}

		if (index != -1) {
			// Read until end of function call (possibly over muiltiple lines)
			// and remove all of it.
			auto func = parseFunctionCall(tokens, tok);
			writeln(func);
		}

		if (tokens.empty)
			break;

		tokens.popFront();
	}

	return "";
}

struct FunctionCall {
	string functionName;
	string[] args = new string[0];
}
FunctionCall parseFunctionCall(R)(ref R tokens, ref Token nameTok)
	if (isInputRange!R)
{
	auto call = FunctionCall();
	call.functionName = nameTok.text;

	assert(tokens.front.text == "gdk_window_process_updates");
	assert(tokens.front == nameTok);

	tokens.popFront();
	assert(tokens.front.text == "(");
	tokens.popFront();

	int curArg = 0;
	int identLevel = 0;
	size_t currectArgStart = 0;
	size_t endOfLastArg = tokens.front.start;
	while (!tokens.empty) {
		if (tokens.front.text == ")") {
			if (identLevel == 0) {
				// End of the function call
				call.args ~= tokens.input[endOfLastArg..tokens.front.start];
				break;
			}

			identLevel --;
		} else if (tokens.front.text == "(") {
			identLevel ++;
		} else if (tokens.front.text == ",") {
			if (identLevel == 0) {
				// End of argument
				call.args ~= tokens.input[endOfLastArg..tokens.front.start];
				endOfLastArg = tokens.front.end;
			}
		}

		tokens.popFront();
	}

	return call;
}
