import std.file;
import std.stdio;
import std.string;

void portFile(string filename) {
	// For better debuggability, we read the entire file into memory once,
	// then look at it and mutate it a bunch of times, then write it back.
	string contents = readText(filename);

	contents = fixBoxApi(contents);
	contents = removeBorderWidth(contents);
	contents = fixGtkInit(contents);
	contents = fixCssProvider(contents);
	contents = fixShowAll(contents);

	// Write result back
	std.file.write(filename, contents);
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


pure @nogc
size_t skipToNested(string line, char c, int nOccurrences, size_t start = 0) {
	size_t index = start;

	assert(start < line.length);

	size_t parenLevel = 0;
	int occurrences = 0;
	for (auto i = start; i < line.length; i ++) {
		switch(line[i]) {
			case '(':
				parenLevel ++;
				break;
			case ')':
				parenLevel --;
				break;
			default:
				if (line[i] == c && parenLevel == 0) {
					occurrences ++;
					if (occurrences == nOccurrences)
						return i;
				}
		}
	}
	return -1;
}
unittest {
	assert(skipToNested("foo(foo(a,b),c)", ',', 1) == cast(size_t)-1);
	assert(skipToNested("foo(foo(a,b),c)", ',', 1, 4) == 12);
}
