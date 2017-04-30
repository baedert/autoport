import std.file;
import std.stdio;
import std.string;

void portFile(string filename) {
	string contents = readText(filename);


	// Write result back
	std.file.write(filename, contents);
}
