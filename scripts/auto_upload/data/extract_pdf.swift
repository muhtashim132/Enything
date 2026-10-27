import PDFKit
import AppKit
import Foundation

let pdfPath = "/Users/muhtaashimnazki/Downloads/Enything/scripts/auto_upload/data/Foodies_by_Chillax_12_Page_Final_Menu.pdf"
let outDir = "/Users/muhtaashimnazki/Downloads/Enything/scripts/auto_upload/data/foodies_pages"

let fileManager = FileManager.default
try? fileManager.createDirectory(atPath: outDir, withIntermediateDirectories: true, attributes: nil)

let pdfUrl = URL(fileURLWithPath: pdfPath)
guard let doc = PDFDocument(url: pdfUrl) else {
    print("Failed to open PDF")
    exit(1)
}

print("Total pages in PDF: \(doc.pageCount)")

for i in 0..<doc.pageCount {
    guard let page = doc.page(at: i) else { continue }
    let pageRect = page.bounds(for: .mediaBox)
    let scale: CGFloat = 2.0
    let targetSize = NSSize(width: pageRect.width * scale, height: pageRect.height * scale)
    
    let image = NSImage(size: targetSize)
    image.lockFocus()
    
    guard let context = NSGraphicsContext.current?.cgContext else { continue }
    context.setFillColor(NSColor.white.cgColor)
    context.fill(CGRect(origin: .zero, size: targetSize))
    context.scaleBy(x: scale, y: scale)
    page.draw(with: .mediaBox, to: context)
    image.unlockFocus()
    
    if let tiff = image.tiffRepresentation,
       let rep = NSBitmapImageRep(data: tiff),
       let jpeg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.9]) {
        let outPath = "\(outDir)/page_\(i+1).jpg"
        let outUrl = URL(fileURLWithPath: outPath)
        try? jpeg.write(to: outUrl)
        print("Page \(i+1) exported: \(outPath)")
    }
}
print("Done extracting all pages!")
