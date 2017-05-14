import std.stdio;


pure @nogc string
getFileExtension(string filename) {
	import std.string: lastIndexOf;
	return filename[filename.lastIndexOf('.') + 1..$];
}
unittest {
	assert("foo.txt".getFileExtension() == "txt");
}


void main(string[] args) {
	if (args.length < 2) {
		writeln("No input files given");
		return;
	}

	foreach (string filename; args[1..$]) {
		writeln("Porting ", filename, "...");
		auto ext = filename.getFileExtension();

		switch(ext) {
			case "c": {
				import c;
				portFile(filename);
			}
			break;

			//case "ui": {
				//import ui;
				//portFile(filename);
			//}
			//break;

			//case "vala": {
				//import vala;
				//portFile(filename);
			//}
			//break;

			/*
			case "cpp":
			case "cxx":
			case "cc": {
			}
			break;
			*/

			default:
			writeln("Error: Unhandled file type '", ext, "' for file ", filename);
			return;
		}
	}
}
