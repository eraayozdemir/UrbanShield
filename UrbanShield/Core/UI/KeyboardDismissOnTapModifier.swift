//
//  KeyboardDismissOnTapModifier.swift
//  UrbanShield
//

import SwiftUI
import UIKit

extension View {
    func dismissKeyboardOnTap() -> some View {
        background(KeyboardDismissTapInstaller())
    }
}

private struct KeyboardDismissTapInstaller: UIViewRepresentable {
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false

        DispatchQueue.main.async {
            context.coordinator.installIfNeeded(from: view)
        }

        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        DispatchQueue.main.async {
            context.coordinator.installIfNeeded(from: uiView)
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        private weak var installedWindow: UIWindow?
        private weak var gestureRecognizer: UITapGestureRecognizer?

        func installIfNeeded(from view: UIView) {
            guard let window = view.window else { return }

            if installedWindow === window, gestureRecognizer != nil {
                return
            }

            let recognizer = UITapGestureRecognizer(target: self, action: #selector(handleTap))
            recognizer.cancelsTouchesInView = false
            recognizer.delegate = self

            window.addGestureRecognizer(recognizer)
            installedWindow = window
            gestureRecognizer = recognizer
        }

        @objc private func handleTap() {
            installedWindow?.endEditing(true)
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            !touch.viewContainsTextInput
        }
    }
}

private extension UITouch {
    var viewContainsTextInput: Bool {
        var currentView = view

        while let candidate = currentView {
            if candidate is UITextField || candidate is UITextView || candidate is UISearchBar {
                return true
            }

            currentView = candidate.superview
        }

        return false
    }
}
