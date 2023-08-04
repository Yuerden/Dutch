//
//  ContentView.swift
//  Dutch
//
//  Created by Johnci on 7/31/23.
//

import SwiftUI
import UIKit
import VeryfiSDK

struct ContentView: View {
    @State private var image: Image?
    @State private var showingImagePickerForCamera = false
    @State private var showingImagePickerForLibrary = false
    @State private var inputImage: UIImage?
    @State private var showConfirmationButton = false
    @State private var showResult = false
    @State private var result: String = ""
    @State private var showScanScreen = false
    @State private var lineItems: [LineItem] = []
    @State private var subtotal: Float = 0
    @State private var tax: Float = 0
    @State private var total: Float = 0
    @State private var vendor: Vendor = Vendor(name: "", type: "")
    @State private var loadingScan = false

    var body: some View {
        VStack {
            image?
                .resizable()
                .scaledToFit()

            if showConfirmationButton {
                Button("Use this Image?") {
                    self.showConfirmationButton = false // reset the confirmation button state
                    if let inputImage = self.inputImage,
                       let imageData = convertImageToJPEG(image: inputImage) {
                        print("Attempting to upload")
                        uploadImageToVeryfi(imageData: imageData)
                        self.inputImage = nil // Reset input image
                        self.image = nil // Reset image
                    }
                }
            } else {
                Button("Take Photo") {
                    self.showingImagePickerForCamera = true
                }

                Button("Select Image") {
                    self.showingImagePickerForLibrary = true
                }
            }
        }
        .sheet(isPresented: $showingImagePickerForCamera, onDismiss: loadImage) {
            ImagePicker(image: self.$inputImage, sourceType: .camera)
        }
        .sheet(isPresented: $showingImagePickerForLibrary, onDismiss: loadImage) {
            ImagePicker(image: self.$inputImage, sourceType: .photoLibrary)
        }
        .sheet(isPresented: $showScanScreen) {
            if loadingScan {
                ProgressView()  // show an activity indicator while data is loading
            } else {
                ScanScreen(lineItems: self.lineItems, subtotal: self.subtotal, tax: self.tax, total: self.total, vendor: self.vendor)
            }
        }
    }


    func loadImage() {
        guard let inputImage = inputImage else { return }
        image = Image(uiImage: inputImage)
        print("Image Loaded!")
        self.showConfirmationButton = true // toggle showConfirmationButton here
    }


    func convertImageToJPEG(image: UIImage, compressionQuality: CGFloat = 1.0) -> Data? {
        print("Image Converted to JPEG")
        return image.jpegData(compressionQuality: compressionQuality)
    }

    func uploadImageToVeryfi(imageData: Data) {
        print("Upload Function starting")
        // Initialize your Veryfi client
        let clientId = ProcessInfo.processInfo.environment["VERYFI_CLIENT_ID"]!
        let clientSecret = ProcessInfo.processInfo.environment["VERYFI_CLIENT_SECRET"]!
        let username = ProcessInfo.processInfo.environment["VERYFI_USERNAME"]!
        let apiKey =  ProcessInfo.processInfo.environment["VERYFI_API_KEY"]!

        let client = Client(clientId: clientId, clientSecret: clientSecret, username: username, apiKey: apiKey)

        self.loadingScan = true  // start loading indicator
        self.showScanScreen = true  // present the sheet immediately

        client.processDocument(fileName: "image", fileData: imageData) { (result) in
            DispatchQueue.main.async {
                switch result {
                case .success(let data):
                    let decoder = JSONDecoder()
                    do {
                        let response = try decoder.decode(Response.self, from: data)
                        self.lineItems = response.line_items
                        self.subtotal = response.subtotal
                        self.tax = response.tax
                        self.total = response.total
                        self.vendor = response.vendor
                        self.loadingScan = false  // stop loading indicator
                    } catch {
                        print("Error decoding data: \(error)")
                    }
                case .failure(let error):
                    print("Error uploading image: \(error)")
                }
            }
        }
    }

}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}

struct ImagePicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Environment(\.presentationMode) private var presentationMode
    var sourceType: UIImagePickerController.SourceType

    func makeUIViewController(context: UIViewControllerRepresentableContext<ImagePicker>) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = self.sourceType
        return picker
    }


    func updateUIViewController(_ uiViewController: UIImagePickerController, context: UIViewControllerRepresentableContext<ImagePicker>) { }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        var parent: ImagePicker

        init(_ parent: ImagePicker) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let uiImage = info[UIImagePickerController.InfoKey.originalImage] as? UIImage {
                parent.image = uiImage
            }

            parent.presentationMode.wrappedValue.dismiss()
        }
    }
}


//JSON Structs
struct Response: Codable {
    let line_items: [LineItem]
    let subtotal: Float
    let tax: Float
    let total: Float
    let vendor: Vendor
}

struct LineItem: Codable, Identifiable {
    let date: String?
    var description: String
    let id: Int
    var total: Float
    let type: String
    let unit_of_measure: String?
    var selectedParticipantId: Int?
}

struct Vendor: Codable {
    let name: String
    let type: String
}


struct ScanScreen: View {
    @State var lineItems: [LineItem]
    @State var subtotal: Float
    @State var tax: Float
    @State var total: Float
    @State var vendor: Vendor

    // Add the participants state
    @State private var participants: [Participant] = []

    // Add the state for transitioning to DelegateScreen
    @State private var showDelegateScreen = false

    var numberFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter
    }

    var body: some View {
        NavigationView {
            List {
                ForEach(lineItems.indices, id: \.self) { index in
                    HStack {
                        TextField("Description", text: $lineItems[index].description)
                        Spacer()
                        TextField("Total", value: $lineItems[index].total, formatter: numberFormatter)
                    }
                }
                .onDelete(perform: deleteItems)
                .onMove(perform: moveItems)

                HStack {
                    Text("Subtotal")
                    Spacer()
                    TextField("Subtotal", value: $subtotal, formatter: numberFormatter)
                }

                HStack {
                    Text("Tax")
                    Spacer()
                    TextField("Tax", value: $tax, formatter: numberFormatter)
                }

                HStack {
                    Text("Total")
                    Spacer()
                    TextField("Total", value: $total, formatter: numberFormatter)
                }

                // Add the Delegate button
                Button("Delegate") {
                    self.showDelegateScreen = true
                }
                .sheet(isPresented: $showDelegateScreen) {
                    DelegateScreen(participants: self.$participants, lineItems: self.$lineItems, subtotal: self.$subtotal, total: self.$total)
                }
            }
            .navigationBarTitle("Scan from: \(vendor.name)", displayMode: .inline)
            .navigationBarItems(leading: EditButton(), trailing:
                Button(action: {
                    withAnimation {
                        let newItem = LineItem(date: "", description: "", id: lineItems.count + 1, total: 0.0, type: "", unit_of_measure: "")
                        lineItems.append(newItem)
                    }
                }) {
                    Label("Add Item", systemImage: "plus")
                }
            )
        }
    }

    func deleteItems(at offsets: IndexSet) {
        lineItems.remove(atOffsets: offsets)
    }

    func moveItems(from source: IndexSet, to destination: Int) {
        lineItems.move(fromOffsets: source, toOffset: destination)
    }
}


struct Participant: Identifiable {
    var id = UUID()
    var name: String
}

struct DelegateScreen: View {
    @Binding var participants: [Participant]
    @Binding var lineItems: [LineItem]
    @Binding var subtotal: Float
    @Binding var total: Float
    @State var selectedParticipantIndex: Int = 0

    @State private var newParticipantName = ""
    @State private var selectedParticipantIndices: [Int: Int] = [:]
    
    @State private var sum: Float = 0
    @State private var percent: Float = 0

    var body: some View {
        NavigationView {
            VStack {
                // Add Participant
                HStack {
                    TextField("Add Friend", text: $newParticipantName)
                    Button(action: {
                        let newParticipant = Participant(name: newParticipantName)
                        participants.append(newParticipant)
                        newParticipantName = ""
                    }) {
                        Text("Add")
                    }
                }
                // Shows Line Items
                List {
                    ForEach(lineItems.indices, id: \.self) { index in
                        HStack {
                            Text(lineItems[index].description)
                            Picker("Participant", selection: Binding(
                                get: { selectedParticipantIndices[lineItems[index].id, default: 0] },
                                set: { newValue in selectedParticipantIndices[lineItems[index].id] = newValue }
                            )) {
                                ForEach(participants.indices, id: \.self) { participantIndex in
                                    Text(participants[participantIndex].name).tag(participantIndex)
                                }
                            }
                        }
                    }
                }
                // Shows Participants
                List {
                    ForEach(participants.indices, id: \.self) { participantIndex in
                        HStack {
                            Text(participants[participantIndex].name)
                            Spacer()
                            Text("$" + String(calculateTotalForParticipant(index: participantIndex)))
                        }
                    }
                }
                //Percentage Complete for total payment
                HStack {
                    Text("Percent Paid")
                    Spacer()
                    Text(String(percent) + "%")
                }
            }
            .navigationBarTitle("Delegate Screen", displayMode: .inline)
            .onReceive([self.lineItems, self.selectedParticipantIndices].publisher.first()) { _ in
                self.updatePercentage()
            }
        }
    }

    // Function to calculate total for a participant
    func calculateTotalForParticipant(index: Int) -> Float {
        var individualTotal: Float = 0.0
        for (lineItemId, participantIndex) in selectedParticipantIndices {
            if participantIndex == index {
                if let lineItem = lineItems.first(where: { $0.id == lineItemId }) {
                    individualTotal += lineItem.total
                }
            }
        }
        let percentage = individualTotal / subtotal
        let unroundedTotal = Double(total * percentage)
        let roundedTotal = round(unroundedTotal * 100) / 100  // rounds to nearest cent
        return Float(roundedTotal)
    }

    //Function to calculate total paid percentage
    func updatePercentage() {
        var sum:Float = 0
        for participantIndex in participants.indices {
            sum = sum + calculateTotalForParticipant(index: participantIndex)
        }
        percent = sum / total * 100
    }
}

