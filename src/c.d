import std.file;
import std.stdio;
import std.string;

void portFile(string filename) {
	// For better debuggability, we read the entire file into memory once,
	// then look at it and mutate it a bunch of times, then write it back.
	string contents = readText(filename);

	contents = fixBoxApi(contents);



	// Write result back
	std.file.write(filename, contents);
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
		// In other words, Everything after the first comma in the
		// gtk_box_ call.
		size_t endIndex = skipToNested(line, ',', line.indexOf('(') + 1);
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
	assert(fixBoxApi("  gtk_box_pack_start(a, b, c, d)") == "  gtk_box_pack_start(a);\n");
}


pure @nogc
size_t skipToNested(string line, char c, size_t start = 0) {
	size_t index = start;

	assert(start < line.length);

	size_t parenLevel = 0;
	for (auto i = start; i < line.length; i ++) {
		switch(line[i]) {
			case '(':
				parenLevel ++;
				break;
			case ')':
				parenLevel --;
				break;
			default:
				if (line[i] == c && parenLevel == 0)
					return i;
		}
	}
	return -1;
}
unittest {
	assert(skipToNested("foo(foo(a,b),c)", ',') == cast(size_t)-1);
	assert(skipToNested("foo(foo(a,b),c)", ',', 4) == 12);
}
