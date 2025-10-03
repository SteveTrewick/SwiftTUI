import Foundation


// Centralise highlight palette calculation so overlays remain visually consistent.
extension ElementStyle {

  static func highlightPalette ( for style: ElementStyle ) -> (foreground: ANSIForecolor, background: ANSIBackcolor) {

    let highlightBackground = ElementStyle.highlightBackcolor ( for: style.foreground )
    let fallbackForeground  = ElementStyle.highlightForecolor ( for: style.background )

    if highlightBackground == style.background {
      // Preserve the previous behaviour of falling back to white when the base style matches the highlight.
      return (fallbackForeground, .white)
    }

    return (fallbackForeground, highlightBackground)
  }

  static func highlightBackcolor ( for forecolor: ANSIForecolor ) -> ANSIBackcolor {
    switch forecolor {
      case .black  : return .black
      case .red    : return .red
      case .green  : return .green
      case .yellow : return .yellow
      case .blue   : return .blue
      case .magenta: return .magenta
      case .cyan   : return .vyan
      case .white  : return .white
    }
  }

  static func highlightForecolor ( for backcolor: ANSIBackcolor ) -> ANSIForecolor {
    switch backcolor {
      case .black  : return .black
      case .red    : return .red
      case .green  : return .green
      case .yellow : return .yellow
      case .blue   : return .blue
      case .magenta: return .magenta
      case .vyan   : return .cyan
      case .white  : return .white
      case .grey   : return .white
    }
  }
}
