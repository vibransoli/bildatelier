import SwiftUI

// Use the public State property-wrapper type explicitly. New SDKs also expose
// a same-name macro whose plug-in may be absent from Command Line Tools.
// The alias avoids that overload without needing any private API or plug-in.
typealias AtelierState<Value> = SwiftUI.State<Value>
