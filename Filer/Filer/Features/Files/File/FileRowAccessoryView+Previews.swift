import SwiftUI

#Preview {
    List {
        FileRowAccessoryView(model: .remote)
        FileRowAccessoryView(model: .progress(fraction: 0.25, label: "1/4"))
        FileRowAccessoryView(model: .local)
        FileRowAccessoryView(model: .failed)
    }
}
