import std.file;
import std.xml;

void portFile(string filename) {
	string contents = readText(filename);

	// Again, for better debuggability, we parse (almost)
	// the same string over and over again.

	contents = removeNoShowAll(contents);


	// Write result back
	std.file.write(filename ~ ".out", contents);
}


string removeNoShowAll(string input) {
	XmlParser parser = XmlParser(input.idup);

	while (!parser.empty) {
		parser.next();
	}

	return parser.input;
}





struct XmlParser {
	struct Element {
		string tagName;
		string[string] props;
	}

	string input;
	Element[] stack;

	@property bool empty = false;

	this(string input) {
		this.input = input;
	}

	void next() {

	}
}
