//
//  QRcode.swift
//  GGEsim
//
//  Created by Tuluobo on 2024/9/18.
//

import Foundation
import UIKit
import CoreImage.CIFilterBuiltins

func generateQRCode(from string: String) -> UIImage {
    
    let context = CIContext()
    let filter = CIFilter.qrCodeGenerator()
    
    filter.message = Data(string.utf8)

    if let outputImage = filter.outputImage {
        if let cgImage = context.createCGImage(outputImage, from: outputImage.extent) {
            return UIImage(cgImage: cgImage)
        }
    }

    return UIImage(systemName: "xmark.circle") ?? UIImage()
}
