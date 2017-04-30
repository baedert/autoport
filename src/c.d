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
