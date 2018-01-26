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
	contents = fixImageApi(contents);
	contents = fixGtkInit(contents);
	contents = fixCssProvider(contents);
	contents = fixShowAll(contents);
	contents = fixMisc(contents);
	contents = removeVoidFunctions(contents);
	contents = replaceFunctions(contents);
	contents = fixRenamedFunctions(contents);
	contents = fixStyleContextApi(contents);
	contents = fixWidgetVfuncs(contents);
	contents = fixMeasure(contents);
	contents = fixSizeAllocate(contents);
	contents = fixSignalConnections(contents);

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
		auto params = line.collectParams();
		if (params.length < 3) {
			// Maybe aleady ported...
			buffer ~= whitespace ~ line ~ "\n";
			lines.popFront();
			continue;
		}
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

	string s = "gtk_style_context_get_color (a, b);";
	assert(fixStyleContextApi(s) == (s ~ "\n"));
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

string fixImageApi(string input) {
	string buffer;

	auto lines = input.lineSplitter();
	string line;
	while (!lines.empty) {
		line = lines.front;
		string func = "gtk_image_new_from_icon_name";
		size_t index = line.indexOf(func);

		if (index == -1) {
			buffer ~= line ~ "\n";
			lines.popFront();
			continue;
		}

		writeln("Found line: ", line);
		writeln("Index: ", index);
		auto whitespace = line[0..index];
		line = lines.collapseToLine(index);

		// Remove the second parameter.
		// In other words, only leave the first parameter, which means
		// we remove everything after the first comma.

		size_t commaIndex = line.indexOf(',');
		if (commaIndex == -1) {
			// Huh?
			writeln(__LINE__, ": No comma found in line '", line, "'");
			buffer ~= line;
			lines.popFront();
			continue;
		}

		// TODO: This is broken if the function call contains another function call.
		size_t endParenIndex = line.indexOf(')');
		auto suffix = line[endParenIndex..$];

		buffer ~= whitespace;
		buffer ~= line[0..commaIndex];
		buffer ~= suffix;
		buffer ~= "\n";
		lines.popFront();
	}

	return buffer;
}
unittest {
	auto result = fixImageApi("    some_func (gtk_image_new_from_icon_name(\"list-add-symbolic\", GTK_ICON_SIZE_FOOBAR));");
	assert(result.startsWith("    some_func "));
	assert(!result.canFind("ICON_SIZE"));
	assert(result.endsWith("));\n"));
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
		"gdk_window_process_all_updates",
		"gdk_window_set_background_pattern",
		"gtk_tree_view_set_rules_hint",
		"gtk_widget_class_install_style_property",
		"gtk_widget_set_clip",
		"gtk_widget_style_get",
		"gtk_widget_set_redraw_on_alloc",
		"gtk_widget_push_composite_child",
		"gtk_widget_pop_composite_child",
		"gtk_widget_add_events",
		"gtk_window_set_wmclass",
		"gdk_window_set_background_rgba"
	];

	string buffer;

	auto lines = input.lineSplitter;
	while (!lines.empty) {
		auto line = lines.front;
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
			lines.popFront();
			continue;
		}

		// The functions listed above should return void
		// and they could span over multiple lines so we need to remove the entire thing.
		auto funcCall = lines.collapseToLine(index);

		// Don't do anything with funcCall sinec we just want to skip it.
		lines.popFront();
	}

	return buffer;
}
unittest {
	assert(removeVoidFunctions("a\ngtk_style_context_set_junction_sides(a,b);\nb") == "a\nb\n");
}

string replaceFunctions(string input) {
	struct Func { string name; string replacement; }
	// These return a value, so we can't just remove the function call altogether.
	// Instead, try to replace them by something remotely useful
	const Func[] funcs = [
		Func("gtk_stock_lookup", "FALSE"),
		Func("gtk_cairo_should_draw_window", "TRUE"),
		Func("gtk_dialog_get_action_area", "gtk_box_new (GTK_ORIENTATION_HORIZONTAL, 0)"), // *shrug*.
		Func("gtk_dialog_get_content_area", "gtk_box_new (GTK_ORIENTATION_HORIZONTAL, 0)"), // *shrug*.
		Func("gtk_container_get_border_width", "0"),
		Func("gtk_label_get_angle", "0"),
		Func("gtk_window_has_toplevel_focus", "FALSE"), // TODO: That's not the actual replacement.
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

string fixRenamedFunctions(string input) {
	struct Func { string name; string replacement; }
	// These have no replacement, but their value can be replaced by a simple TRUE or FALSE.
	// Of course, fixing things that way is not ideal but it makes the project compile.
	const Func[] funcs = [
		Func("gtk_toggle_button_set_inconsistent", "gtk_check_button_set_inconsistent"),
		Func("gtk_toggle_button_get_inconsistent", "gtk_check_button_get_inconsistent"),
		Func("gtk_header_bar_set_show_close_button", "gtk_header_bar_set_show_title_buttons"),
		Func("gtk_style_context_add_provider_for_screen", "gtk_style_context_add_provider_for_display"),
		// These are not equivalent of course, but let's hope this one works out.
		Func("gdk_screen_get_default", "gdk_display_get_default"),
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
		buffer ~= line[index + funcs[funcIndex].name.length..openParenIndex]; // Whitespace
		buffer ~= line[openParenIndex + 0..$];
		buffer ~= "\n";
	}
	return buffer;
}
unittest {
	assert(fixRenamedFunctions("gtk_header_bar_set_show_close_button (FOO (abc), TRUE);\n") ==
	       "gtk_header_bar_set_show_title_buttons (FOO (abc), TRUE);\n");
}

string fixSizeAllocate(string input) {
	string buffer;

	auto lines = input.lineSplitter;
	while (!lines.empty) {
		auto line = lines.front;
		size_t index = line.indexOf("gtk_widget_size_allocate_with_baseline");

		if (index != -1) {
			// Just replace this with gtk_widget_size_allocate.
			buffer ~= line[0..index];
			buffer ~= "gtk_widget_size_allocate";
			buffer ~= line[index + "gtk_widget_size_allocate_with_baseline".length .. $];
			buffer ~= "\n";
			lines.popFront();
			continue;
		}

		index = line.indexOf("gtk_widget_size_allocate");

		if (index == -1) {
			buffer ~= line ~ "\n";
			lines.popFront();
			continue;
		}

		// gtk_widget_size_allocate gained a baseline and an out_param parameter.
		string call = lines.collapseToLine(index);
		auto params = call.collectParams();
		if (params.length == 2) {
			// Not ported yet.
			assert(call[$ - 1] == ';');
			assert(call[$ - 2] == ')');
			buffer ~= line[0..index]; // Whitespace
			buffer ~= call[0..$ - 2];
			// The NULL here will break at runtime, but it will compile.
			buffer ~= ", -1, NULL);";
			lines.popFront();
		} else {
			buffer ~= line ~ "\n";
			lines.popFront();
			continue;
		}
	}
	return buffer;
}

string fixSignalConnections(string input) {
	string buffer;

	auto lines = input.lineSplitter;
	while (!lines.empty) {
		auto line = lines.front;
		auto index = line.indexOf("g_signal_connect");

		if (!line.whitespaceUntil(cast(int)index - 1) ||
		    index == -1) {
			buffer ~= line ~ "\n";
			lines.popFront();
			continue;
		}

		string whitespace = line[0..index];
		string call = lines.collapseToLine(index);
		auto params = call.collectParams();
		if (params.length != 4) {
			buffer ~= line ~ "\n";
			lines.popFront();
			continue;
		}

		string signalName = params[1].strip()[1..$-1];

		// Do all here manually since we don't have a lot of these
		if (signalName == "delete-event") {
			// This only works if the Object we connect to is a GtkWindow of course,
			// but that's the only sane object to connect to delete-event as well.
			buffer ~= whitespace ~ call.replace("delete-event", "close-request") ~ "\n";
		} else {
			// Irrelevant.
			// TODO: This is the 'collapsed' function call, but if we didn't change anything,
			//       we should just save the uncollapsed one.
			buffer ~= whitespace ~ call ~ "\n";
		}

		lines.popFront();
	}

	return buffer;
}
unittest {
	auto result = "   g_signal_connect (G_OBJECT (foo), \"delete-event\",\n G_CALLBACK (PENIS), NULL);"
	              .fixSignalConnections();
	assert(result[0..3] == "   ");
	assert(!result.canFind("delete-event"));
	assert(result.canFind("close-request"));
}


// ----------------------------------------------------------------------------------------
// Utils

pure @nogc
bool whitespaceUntil(string input, int index) {
	import std.ascii: isWhite;
	for (int i = 0 ; i < index; i ++) {
		if (!input[index].isWhite())
			return false;
	}

	return true;
}
unittest {
	assert("    a".whitespaceUntil(3));
	assert(!"    a".whitespaceUntil(4));
}

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

pure
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
	auto params = "foo(a, b)".collectParams();
	assert(params == ["a", " b"]); // Preserves whitespace!
}
