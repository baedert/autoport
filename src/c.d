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
	contents = fixGtkInit(contents);
	contents = fixCssProvider(contents);
	contents = fixShowAll(contents);
	contents = fixMisc(contents);
	contents = removeVoidFunctions(contents);
	contents = replaceFunctions(contents);
	contents = fixStyleContextApi(contents);
	contents = fixWidgetVfuncs(contents);
	contents = fixMeasure(contents);

	// Write result back
	std.file.write(filename, contents);
}

string fixGtkInit(string input) {
	string buffer;

	auto lines = input.lineSplitter;
	while (!lines.empty) {
		string line = lines.front();
		import std.ascii: isWhite;
		size_t index = line.indexOf("gtk_init");

		if (index == -1) {
			buffer ~= line ~ "\n";
			lines.popFront();
			continue;
		}

		auto whitespace = line[0..index];
		bool whitespaceBefore = index > 0 && line[index - 1].isWhite();
		line = lines.collapseToLine(index);

		// fix by removing the parameters entirely
		auto openParenIndex = line.indexOf('(');

		if (openParenIndex == -1 ||
		    (index > 0 && !whitespaceBefore)) {
			// Huh?
			buffer ~= whitespace ~ line ~ "\n";
			lines.popFront();
			continue;
		}

		buffer ~= whitespace ~ line[0..openParenIndex + 1];
		buffer ~= ");\n";

		if (!lines.empty)
			lines.popFront();
	}

	return buffer;
}
unittest {
	assert(fixGtkInit("gtk_init (&argc, &argv);") == "gtk_init ();\n");
	assert(fixGtkInit("dialog_gtk_init (foo);") == "dialog_gtk_init (foo);\n");
}

string fixWidgetVfuncs(string input) {
	import std.ascii: isAlpha;
	const string[] funcs = [
		"get_preferred_width",
		"get_preferred_height",
		"get_preferred_width_for_height",
		"get_preferred_height_for_width",
		"get_preferred_height_and_baseline_for_width",
		"draw"
	];

	string buffer;

	foreach (line; input.lineSplitter()) {
		size_t index;
		size_t funcIndex;

		for (auto i = 0; i < funcs.length; i ++) {
			if ((index = line.indexOf("->" ~ funcs[i])) != -1) {
				funcIndex = i;
				break;
			}
		}

		if (index == -1 ||
		    (index > 0 && line[index - 1] == ')') ||
		    (line[index + funcs[funcIndex].length + 2].isAlpha) ||
		    (line[index + funcs[funcIndex].length + 2] == '_')) {
			buffer ~= line ~ "\n";
			continue;
		}

		// This could be wrong of course...
	}

	return buffer;
}

string fixMeasure(string input) {
	const string[] funcs = [
		"gtk_widget_get_preferred_height_and_baseline_for_width",
		"gtk_widget_get_preferred_width_for_height",
		"gtk_widget_get_preferred_height_for_width",
		"gtk_widget_get_preferred_width",
		"gtk_widget_get_preferred_height",
		"->get_preferred_height_and_baseline_for_width",
		"->get_preferred_width_for_height",
		"->get_preferred_height_for_width",
		"->get_preferred_width",
		"->get_preferred_height"
	];
	string buffer;

	auto lines = input.lineSplitter();
	while (!lines.empty) {
		string line = lines.front;
		size_t index;
		size_t funcIndex;
		bool horizontal = false;
		bool isVfunc = false;
		bool for_size;

		for (int i = 0; i < funcs.length; i ++) {
			if ((index = line.indexOf(funcs[i])) != -1) {
				funcIndex = i;
				if (i >= 5)
					isVfunc = true;
				break;
			}
		}

		if (index == -1) {
				buffer ~= line ~ "\n";
				lines.popFront();
				continue;
		}

		// We could save this manually...
		horizontal = funcs[funcIndex].canFind("_preferred_width");
		for_size = funcs[funcIndex].canFind("_for_");

		auto whitespace = line[0..index];
		line = lines.collapseToLine(index);
		string[] params = line.collectParams();
		int i = 0;

		// Fill up with NULL
		while (params.length < 6)
			params ~= "NULL";

		buffer ~= whitespace;
		if (isVfunc) {
			buffer ~= "->measure (";
		} else {
			buffer ~= "gtk_widget_measure (";
		}

		buffer ~= params[i++] ~ ", " ~
		          (horizontal ? "GTK_ORIENTATION_HORIZONTAL" : "GTK_ORIENTATION_VERTICAL");

		if (for_size) {
			buffer ~= "," ~ params[i++];
		} else {
			buffer ~= ", -1";
		}

		buffer ~= "," ~ params[i]; i++;
		buffer ~= "," ~ params[i]; i++;
		buffer ~= "," ~ params[i]; i++;
		buffer ~= "," ~ params[i]; i++;
		buffer ~= ");\n";

		if (!lines.empty)
			lines.popFront();
	}

	return buffer;
}
unittest {
	//writeln("gtk_widget_get_preferred_height_and_baseline_for_width (widget, 400, &min, &nat, &min_baseline, &nat_baseline)".fixMeasure());
	//writeln("gtk_widget_get_preferred_height (widget, 400, &min, &nat)".fixMeasure());
	//writeln("GTK_WIDGET_CLASS(my_class)->get_preferred_width(widget, NULL, &nat);".fixMeasure());
}

string fixStyleContextApi(string input) {
	const string[] funcs = [
		"gtk_style_context_get_color",
		"gtk_style_context_get_border",
		"gtk_style_context_get_padding",
		"gtk_style_context_get_margin",
		"gtk_style_context_get_background_color", // Already deprecated will go away.
	];
	string buffer;

	auto lines = input.lineSplitter();
	string line;
	while (!lines.empty) {
		line = lines.front();
		import std.ascii: isWhite;

		size_t index;
		size_t funcIndex;
		for (int i = 0; i < funcs.length; i ++) {
			if ((index = line.indexOf(funcs[i])) != -1) {
				funcIndex = i;
				break;
			}
		}
		if (index == -1) {
			buffer ~= line ~ "\n";
			lines.popFront();
			continue;
		}

		auto whitespace = line[0..index];
		line = lines.collapseToLine(index);
		// This function lost its *middle* parameter.
		size_t openParenIndex = line.indexOf('(');
		size_t firstCommaIndex = line.skipToNested(',', 1, openParenIndex + 1);
		size_t secondCommaIndex = line.skipToNested(',', 1, firstCommaIndex + 1);
		buffer ~= whitespace;
		buffer ~= line[0..firstCommaIndex + 1];
		buffer ~= line[secondCommaIndex + 1 .. $];
		buffer ~= "\n";

		if (!lines.empty)
			lines.popFront();
	}

	return buffer;
}
unittest {
	assert(fixStyleContextApi("gtk_style_context_get_color(a, b | foo(abc), &d);") == "gtk_style_context_get_color(a, &d);\n");
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

		// TODO: This doesn't work over multiple lines.

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

	auto lines = input.lineSplitter();
	string line;
	while (!lines.empty) {
		line = lines.front;
		string func = "gtk_box_pack_start";
		size_t index = line.indexOf("gtk_box_pack_start");
		if (index == -1) {
			index = line.indexOf("gtk_box_pack_end");
			func = "gtk_box_pack_end";
		}

		if (index == -1) {
			buffer ~= line ~ "\n";
			lines.popFront();
			continue;
		}

		auto whitespace = line[0..index];
		line = lines.collapseToLine(index);
		// Remove last 3 parameters
		// In other words, Everything after the second comma in the
		// gtk_box_ call. First the instance, then the child.
		size_t endIndex = skipToNested(line, ',', 2, line.indexOf('(') + 1);
		if (endIndex == cast(size_t)-1) {
			// No comma found. Already ported?
			buffer ~= line ~ "\n";
			lines.popFront();
			continue;
		}

		buffer ~= whitespace;
		buffer ~= line[0..endIndex];
		buffer ~= ");\n";
		lines.popFront();
	}

	return buffer;
}
unittest {
	assert(fixBoxApi("  gtk_box_pack_start(a, b, c, d);") == "  gtk_box_pack_start(a, b);\n");
	assert(fixBoxApi("gtk_box_pack_start(a, b, c, d, e);") == "gtk_box_pack_start(a, b);\n");
	assert(fixBoxApi("gtk_box_pack_end(a,b,\nc,d,e);") == "gtk_box_pack_end(a,b);\n");
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

// These functions have no replacement and they return void
// so we can just remove the line(s) they occur on.
string removeVoidFunctions(string input) {
	const string[] funcs = [
		"gtk_style_context_set_junction_sides",
		"gtk_button_set_always_show_image",
		"gtk_container_set_border_width",
		"gtk_expander_set_spacing",
		"gtk_widget_set_no_show_all",
		"gtk_button_set_image",
		"gtk_widget_set_allocation",
		"gtk_box_set_center_widget",
		"gtk_label_set_angle",
		"gtk_container_class_handle_border_width",
		"gtk_style_context_invalidate",
		"gtk_window_set_has_resize_grip",
		"gtk_tree_view_set_rules_hint",
		"gdk_window_process_updates",
		"gdk_window_set_background_pattern"
	];

	string buffer;

	foreach (line; input.lineSplitter()) {
		size_t index;
		size_t funcIndex;

		for (auto i = 0; i < funcs.length; i ++) {
			if ((index = line.indexOf(funcs[i])) != -1) {
				funcIndex = i;
				break;
			}
		}

		if (index == -1) {
			buffer ~= line ~ "\n";
			continue;
		}
	}

	return buffer;
}
unittest {
	assert(removeVoidFunctions("a\ngtk_style_context_set_junction_sides(a,b);\nb") == "a\nb\n");
}

string replaceFunctions(string input) {
	struct Func { string name; string replacement; }
	// These have no replacement, but their value can be replaced by a simple TRUE or FALSE.
	// Of course, fixing things that way is not ideal but it makes the project compile.
	const Func[] funcs = [
		Func("gtk_stock_lookup", "FALSE"),
		Func("gtk_cairo_should_draw_window", "TRUE"),
		Func("gtk_dialog_get_action_area", "gtk_box_new (GTK_ORIENTATION_HORIZONTAL, 0)"), // *shrug*.
		Func("gtk_dialog_get_content_area", "gtk_box_new (GTK_ORIENTATION_HORIZONTAL, 0)"), // *shrug*.
		Func("gtk_container_get_border_width", "0"),
		Func("gtk_label_get_angle", "0"),
		Func("gtk_window_has_toplevel_focus", "FALSE") // TODO: That's not the actual replacement.
	];
	string buffer;

	foreach (line; input.lineSplitter) {
		size_t index;
		size_t funcIndex;

		for (auto i = 0; i < funcs.length; i ++) {
			if ((index = line.indexOf(funcs[i].name)) != -1) {
				funcIndex = i;
				break;
			}
		}

		if (index == -1) {
			buffer ~= line ~ "\n";
			continue;
		}

		// Replace function call with replacement
		size_t openParenIndex =  line[index..$].indexOf('(') + index;
		size_t closeParenIndex = line.skipToNested(')', 0, openParenIndex + 1);
		buffer ~= line[0..index];
		buffer ~= funcs[funcIndex].replacement;
		buffer ~= line[closeParenIndex + 1..$];
		buffer ~= "\n";
	}
	return buffer;
}
unittest {
	assert(replaceFunctions("if (!gtk_stock_lookup (foo, bla)) {") == "if (!FALSE) {\n");
}


// ----------------------------------------------------------------------------------------
// Utils

pure @nogc
size_t skipToNested(string line, char needle, int nOccurrences, size_t start = 0) {
	size_t index = start;

	assert(start < line.length);

	int parenLevel = 0;

	int occurrences = 0;
	for (auto i = start; i < line.length; i ++) {
		auto c = line[i];
		//writeln(c, ", occ: ", occurrences, ", level: ", parenLevel);

		if (c == needle && parenLevel == 0) {
			occurrences ++;
			if (occurrences == nOccurrences)
				return i;
		}

		if (c == '(') {
			parenLevel ++;
		} else if (c == ')') {
			if (c == needle && parenLevel == 0)
				return i;

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

// TODO: accept an end character?
pure
string collapseToLine(R)(ref R input, size_t start_index)
	if (isInputRange!R)
{
	assert(!input.empty);
	assert(start_index < input.front.length);

	string buffer = input.front[start_index..$];

	if (buffer.canFind(';'))
		return buffer;


	input.popFront();
	while (!input.empty) {
		string line = input.front;
		size_t start = line.skipToNonWhitespace();
		if (start == -1) {
			// Just whitespace...
			input.popFront();
			continue;
		}
		buffer ~= line[start..$];

		if (line.canFind(';'))
			break;

		input.popFront();
	}

	return buffer;
}
unittest {
	string fo = "foo(a,\nb, c, d,\ne);";
	auto lines = fo.lineSplitter;
	string oneLine = lines.collapseToLine(0);
}

//pure
string[] collectParams(string input) {
	size_t openParen = input.indexOf('(');
	size_t closeParen = input.lastIndexOf(')');
	size_t[] commaIndices =[openParen];

	if (openParen == -1)
		return [];

	assert(!input.canFind("\n"));

	int occ = 1;
	size_t index;
	while((index = skipToNested(input, ',', occ, openParen + 1)) != -1) {
		commaIndices ~= index;
		occ ++;
	}

	commaIndices ~= closeParen;

	//writeln(input);
	//writeln(commaIndices);

	string[] params;

	for (int i = 1; i < commaIndices.length; i ++) {
		params ~= input[commaIndices[i -1]+1..commaIndices[i]];
	}

	return params;
}
unittest {
	"foo(a, b)".collectParams();
}
