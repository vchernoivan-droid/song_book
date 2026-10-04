import 'dart:io';
import 'dart:typed_data';

void main(List<String> args) {
  final images = args.skip(1).map(File.new).map((f) => f.readAsBytesSync()).toList();

  final directory = BytesBuilder();
  void u16(int v) => directory.add([v & 0xFF, (v >> 8) & 0xFF]);
  void u32(int v) => directory.add([v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF]);

  u16(0);
  u16(1);
  u16(images.length);

  var offset = 6 + images.length * 16;
  for (final image in images) {
    final side = _pngSide(image);
    // 0 в поле размера — это 256, в один байт больше не влезает
    directory.add([side == 256 ? 0 : side, side == 256 ? 0 : side, 0, 0]);
    u16(1);
    u16(32);
    u32(image.length);
    u32(offset);
    offset += image.length;
  }

  for (final image in images) {
    directory.add(image);
  }

  File(args.first).writeAsBytesSync(directory.takeBytes());
}

int _pngSide(Uint8List png) => ByteData.sublistView(png, 16, 20).getUint32(0);
