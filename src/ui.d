import std.string;
import std.algorithm;
import std.stdio;

void portFile(string filename) {
	import std.file;
	string contents = readText(filename);

	// Again, for better debuggability, we parse (almost)
	// the same string over and over again.
	contents = removeProps(contents);
	contents = removeSignals(contents);
	contents = removeBoxChildProps(contents);
	contents = removeBoxCenterChild(contents);
	contents = fixRemovedMargins(contents);
	contents = fixCloseButtonApi(contents);

	// Write result back
	//std.file.write(filename ~ ".out", contents);
	std.file.write(filename, contents);
}

string fixRemovedMargins(string input) {
	XmlParser parser = XmlParser(input.idup);
	parser.parseAll();

	foreach (ref line; parser.lineStack) {
		if (line.type == LineType.PROPERTY) {
			auto parsed = parseXmlLine(line);
			string *v;
			if ((v = "name" in parsed.props) != null) {
				if (*v == "margin_left" ||
				    *v == "margin-left") {
					line.data = line.data.replace("left", "start"); // :]
				} else if (*v == "margin_right" ||
				           *v == "margin-right") {
					line.data = line.data.replace("right", "end");
				}
			}
		}
	}

	return parser.toString();
}

string removeProps(string input) {
	immutable string[] funcsToRemove = [
		"no_show_all",
		"no-show-all",
		"app_paintable",
		"app-paintable",
		"ignore_hidden",
		"ignore-hidden",
		"border_width",
		"border-width",
		"stock_size",
		"stock-size"
	];
	XmlParser parser = XmlParser(input.idup);
	parser.parseAll();

	foreach (ref line; parser.lineStack) {
		if (line.type == LineType.PROPERTY) {
			auto parsed = parseXmlLine(line);
			string *v;
			if ((v = "name" in parsed.props) != null) {
				if (funcsToRemove.canFind(*v)) {
					parser.removeLine(line);
				}
			}
		}
	}

	return parser.toString();
}

string removeSignals(string input) {
	immutable string[] funcsToRemove = [
		"delete-event", // TODO: We could replace these with GtkWindow::close-request
		"delete_event",
		"button-press-event",
		"button_press_event",
		"button-release-event",
		"button_press_event",
		"motion-notify-event",
		"motion_notify_event",
		"focus-in-event",
		"focus_in_event",
		"focus-out-event",
		"focus_out_event",
		"event-after",
		"event_after",
		"grab-broken-event",
		"grab_broken_event",
		"map-event",
		"map_event",
		"unmap-event",
		"unmap_event",
		"destroy-event",
		"destroy_event",
		"scroll-event",
		"scroll_event",
		"touch-event",
		"touch_event",
		"configure-event",
		"configure_event",
		"proximity-in-event",
		"proximity_in_event",
		"proximity-out-event",
		"proximity_out_event",
	];
	XmlParser parser = XmlParser(input.idup);
	parser.parseAll();

	foreach (ref line; parser.lineStack) {
		if (line.type == LineType.SIGNAL) {
			auto parsed = parseXmlLine(line);
			string *v;
			if ((v = "name" in parsed.props) != null) {
				if (funcsToRemove.canFind(*v)) {
					parser.removeLine(line);
				}
			}
		}
	}

	return parser.toString();
}

string removeBoxChildProps(string input) {
	XmlParser parser = XmlParser(input.idup);
	parser.parseAll();

	foreach (ref line; parser.lineStack) {
		if (line.type == LineType.PACKING_PROPERTY) {
			auto parsed = parseXmlLine(line);
			string *v;
			if ((v = "name" in parsed.props) != null) {
				if (*v == "fill" || *v =="expand") {
					// 'fill' and 'expand' child properties in GtkBox
					// and GtkButtonBox are gone...
					auto parent = parser.prevParent(line, LineType.OBJECT, -3);
					if (parent != parser.garbage) {
						auto parsedParent = parseXmlLine(parent);

						if (parsedParent.props["class"] == "GtkBox" ||
						    parsedParent.props["class"] == "GtkButtonBox") {
							parser.removeLine(line);
						}
					}
				}
			}
		}
	}

	return parser.toString();
}

string removeBoxCenterChild(string input) {
	XmlParser parser = XmlParser(input.idup);
	parser.parseAll();

	foreach (ref line; parser.lineStack) {
		if (line.type == LineType.CHILD) {
			auto parsed = parseXmlLine(line);
			string *v;
			if ((v = "type" in parsed.props) != null) {
				if (*v == "center") {
					// <child type="center">
					// Now check if it's inside a GtkBox. If so, remove the type parameter.
					auto parent = parser.prevParent(line, LineType.OBJECT, -1);
					auto parsedParent = parseXmlLine(parent);
					if ("class" !in parsedParent.props)
						continue;

					if (parsedParent.props["class"] == "GtkBox") {
						// The current line is a <child> of a GtkBox with
						// type set to "center". However, in gtk4, GtkBox
						// does not have a center child anymore.
						auto startIndex = line.data.indexOf('<');
						string whitespace = line.data[0..startIndex];
						line.data = whitespace ~ "<child>";
					}
				}
			}
		}
	}

	return parser.toString();
}

string fixCloseButtonApi(string input) {
	// Due to unclear API naming, GtkHeaderBar:show-close-button has been renamed in GTK4
	// to GtkHeaderBar:show-title-buttons, which means that the former won't work anymore in UI files.
	XmlParser parser = XmlParser(input.idup);
	parser.parseAll();

	// Unfortunately, the "show-close-button" property name isn't unique even inside GTK+,
	// GtkSearchBar has one like that too.
	foreach (ref line; parser.lineStack) {
		if (line.type == LineType.PROPERTY) {
			auto parent= parser.prevParent(line, LineType.OBJECT, -1);

			if (parent != parser.garbage) {
				auto parsedParent = parseXmlLine(parent);

				// We can only fix these for GtkHeaderBar instances.
				if (parsedParent.props["class"] != "GtkHeaderBar")
					continue;
			}

			auto parsed = parseXmlLine(line);
			string *v;
			if ((v = ("name" in parsed.props)) != null) {
				if (*v == "show-close-button") {
					line.data = line.data.replace("show-close-button", "show-title-buttons");
				} else if (*v == "show_close_button") {
					line.data = line.data.replace("show_close_button", "show-title-buttons");
				}
			}
		}
	}

	return parser.toString();
}
unittest {
	assert(fixCloseButtonApi("<object class=\"GtkHeaderBar\">\n<property name=\"show_close_button\">1</property>\n") ==
	       "<object class=\"GtkHeaderBar\">\n<property name=\"show-title-buttons\">1</property>\n");
	// Leave non-headerbars alone
	assert(fixCloseButtonApi("<object class=\"GtkSearchBar\">\n<property name=\"show_close_button\">1</property>\n") ==
	       "<object class=\"GtkSearchBar\">\n<property name=\"show_close_button\">1</property>\n");
}

enum LineType {
	CRAP,
	EMPTY,
	OTHER, /* Unhandled by us */
	CHILD,
	CHILD_END,
	OBJECT,
	OBJECT_END,
	PACKING,
	PACKING_END,
	PROPERTY,
	PROPERTY_END,
	PACKING_PROPERTY,
	PACKING_PROPERTY_END,
	SIGNAL,
}

struct XmlLine {
	size_t index;
	string data;
	LineType type;
	uint depth;
}

struct XmlParser {
	XmlLine[] lineStack;

	XmlLine garbage = XmlLine();

	string input;
	this(string input) {
		this.input = input;
	}


	void removeLine(ref XmlLine line) {
		//import std.algorithm;
		//this.lineStack = lineStack.remove(line.index);
		lineStack[line.index].type = LineType.CRAP;
	}

	uint curDepth = 0;
	private void appendLine(string data, LineType type) {
		lineStack ~= XmlLine(lineStack.length, data, type, curDepth);
	}

	private void parseAll() {
		import std.stdio;
		foreach (string line; input.lineSplitter) {
			if (line.strip().length == 0) {
				appendLine(line, LineType.EMPTY);
				continue;
			}

			auto startIndex = line.indexOf('<');
			if (startIndex == -1) {
				appendLine(line, LineType.OTHER);
				continue;
			}

			bool isEnd = false;
			if (line[startIndex + 1] == '/') {
				isEnd = true;
				startIndex ++;
			}

			string ident = parseToken(line[startIndex + 1..$]);
			if (ident == "object") {
				auto type = isEnd ? LineType.OBJECT_END : LineType.OBJECT;

				if (isEnd)
					curDepth --;

				appendLine(line, type);

				if (!isEnd)
					curDepth ++;
			} else if (ident == "child") {
				auto type = isEnd ? LineType.CHILD_END : LineType.CHILD;

				if (isEnd)
					curDepth --;

				appendLine(line, type);

				if (!isEnd)
					curDepth++;
			} else if (ident == "packing") {
				auto type = isEnd ? LineType.PACKING_END : LineType.PACKING;

				if (isEnd)
					curDepth --;

				appendLine(line, type);

				if (!isEnd)
					curDepth ++;
			} else if (ident == "property") {
				// XXX We don't support properties over multiple lines!
				LineType type = LineType.OTHER;
				bool childProp = lineStack[$ - 1].type == LineType.PACKING ||
				                 lineStack[$ - 1].type == LineType.PACKING_PROPERTY;

				if (childProp)
					type = LineType.PACKING_PROPERTY;
				else
					type = isEnd ? LineType.PROPERTY_END : LineType.PROPERTY;

				appendLine(line, type);
			} else if (ident == "signal") {
				auto type = LineType.SIGNAL;

				appendLine(line, type);
			} else {
				appendLine(line, LineType.OTHER);
			}
		}
	}

	public ref XmlLine prevParent(const ref XmlLine start, LineType type, int levelDiff) {
		import std.stdio;
		int i = cast(int)start.index;

		while (i >= 0 && lineStack[i].depth >= start.depth + levelDiff) {
			if (lineStack[i].depth == start.depth + levelDiff &&
			    lineStack[i].type == type) {
				return lineStack[i];
			}
			i --;
		}

		return garbage;
	}

	public string toString() {
		import std.range;
		import std.array;
		import std.algorithm;

		return lineStack.filter!(a => a.type != LineType.CRAP).map!(a => a.data).join("\n") ~ "\n";
	}
}

struct ParsedLine {
	string whitespace;
	string name;
	string text;
	string[string] props;
	bool end;
}

ParsedLine parseXmlLine(ref XmlLine inputLine) {
	auto startIndex = inputLine.data.indexOf('<');

	ParsedLine result;

	if (startIndex == -1) {
		import std.stdio;
		writeln("Malformed line: ", inputLine.data);
		assert(0);
	}

	if (startIndex > 0) {
		result.whitespace = inputLine.data[0..startIndex];
	}

	if (inputLine.data[startIndex + 1] == '/') {
		result.end = true;
		startIndex ++;
	}

	result.name = parseToken(inputLine.data[startIndex + 1..$]);

	auto endIndex = inputLine.data.indexOf('>');

	if (inputLine.data[endIndex - 1] != '/' &&
	    endIndex < inputLine.data.length - 1) {
		auto endTagStart = inputLine.data.indexOf('<', endIndex + 1);
		if (endTagStart != -1) {
			// -1 happens e.g. for "label" properties with multiline strings.
			result.text = inputLine.data[endIndex + 1..endTagStart];
		}
	}

	// Now parse the properties...
	// TODO: Support more than one...
	//import std.stdio;
	size_t pos = startIndex + 1 + result.name.length + 1;
	if (pos >= inputLine.data.length - 1) {
		return result;
	}
	string propName = parseToken(inputLine.data[pos..$]);
	//writeln(propName);
	pos += propName.length;
	if (pos > inputLine.data.length - 1) {
	  writeln("propName: ", propName);
	  writeln(inputLine.data);
	  writeln(inputLine);
	}
	assert(inputLine.data[pos] == '=');
	pos ++;
	pos = inputLine.data.indexOf('"', pos); // Skip to "
	assert(inputLine.data[pos] == '"');
	pos ++;
	string propValue = parseToken(inputLine.data[pos..$]);
	//writeln(propValue);
	result.props[propName] = propValue;

	return result;
}
unittest {
	auto testLine = XmlLine(0, "<property name=\"foo\">zomg</property>");

	ParsedLine parsed = parseXmlLine(testLine);

	assert(parsed.name == "property");
	assert(!parsed.end);
	assert(parsed.whitespace.length == 0);
	assert(parsed.text == "zomg");
	assert(parsed.props.length == 1);
	assert(parsed.props["name"] == "foo");

	testLine = XmlLine(0, "<signal name=\"delete-event\" handler=\"foobar\" />");
	parsed = parseXmlLine(testLine);
	assert(parsed.name == "signal");
	assert(parsed.props["name"] == "delete-event");
}

pure @nogc splitsXml(char c) {
	return c == ' '  ||
	       c == '\t' ||
	       c == '\n' ||
	       c == '='  ||
	       c == '"'  ||
	       c == '>'  ||
	       c == '<'  ||
	       c == '\'';
}

pure
string parseToken(string input) {
	string back;

	size_t i = 0;
	while (i < input.length && !splitsXml(input[i])) {
		back ~= input[i];
		i ++;
	}
	return back;
}
