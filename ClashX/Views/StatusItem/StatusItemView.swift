//
//  StatusItemView.swift
//  ClashX
//
//  Created by CYC on 2018/6/23.
//  Copyright © 2018年 yichengchen. All rights reserved.
//
//  Thanks https://github.com/exelban/stats

import AppKit
import Foundation

@MainActor
final class StatusItemView: NSView, StatusItemViewProtocol {
    private var statusItem: NSStatusItem?

    private var up: Int = 0
    private var down: Int = 0
    private var showSpeed: Bool = true
    private var enableProxy: Bool = false

    private let horizontalPadding: CGFloat = 3
    private let iconSize: CGFloat = 16
    private let itemHeight: CGFloat = 22
    private let textFont = StatusItemTool.font
    private lazy var iconImage: NSImage = StatusItemTool.menuImage

    static func create(statusItem: NSStatusItem?) async -> StatusItemView {
        let view = StatusItemView(frame: NSRect(x: 0, y: 0, width: statusItemLengthWithSpeed, height: 22))
        view.statusItem = statusItem

        guard let button = statusItem?.button, let itemView = button.superview else {
            Logger.log("button = nil")
            await ConfigFileManager.shared.openConfigFolder()
            return view
        }

        itemView.subviews.filter { $0 is StatusItemView }.forEach { $0.removeFromSuperview() }
        itemView.addSubview(view)
        view.updateViewStatus(enableProxy: false)
        return view
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: frame.width, height: itemHeight)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let sharedColor = enableProxy ? NSColor.labelColor : NSColor.labelColor.withSystemEffect(.disabled)

        let iconRect = CGRect(
            x: horizontalPadding,
            y: floor((bounds.height - iconSize) * 0.5),
            width: iconSize,
            height: iconSize
        )
        NSGraphicsContext.saveGraphicsState()
        sharedColor.set()
        iconRect.fill()
        iconImage.draw(in: iconRect, from: .zero, operation: .destinationIn, fraction: 1.0)
        NSGraphicsContext.restoreGraphicsState()

        guard showSpeed else { return }

        let upText = SpeedUtils.getSpeedString(for: up)
        let downText = SpeedUtils.getSpeedString(for: down)
        let style = NSMutableParagraphStyle()
        style.alignment = .right

        let attributes: [NSAttributedString.Key: Any] = [
            .font: textFont,
            .foregroundColor: sharedColor,
            .paragraphStyle: style
        ]

        let upAttributed = NSAttributedString(string: upText, attributes: attributes)
        let downAttributed = NSAttributedString(string: downText, attributes: attributes)
        let maxDimension: CGFloat = CGFloat.greatestFiniteMagnitude

        let upSize = upAttributed.boundingRect(
            with: CGSize(width: maxDimension, height: maxDimension),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        ).integral.size
        let downSize = downAttributed.boundingRect(
            with: CGSize(width: maxDimension, height: maxDimension),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        ).integral.size

        let textWidth = max(upSize.width, downSize.width)
        let textRight = bounds.width - horizontalPadding
        let textX = textRight - textWidth
        let textHeight = max(upSize.height, downSize.height)
        let upRect = CGRect(x: textX, y: 12, width: textWidth, height: textHeight)
        let downRect = CGRect(x: textX, y: 2, width: textWidth, height: textHeight)

        upAttributed.draw(with: upRect)
        downAttributed.draw(with: downRect)
    }

    func updateSize(_ statusItem: NSStatusItem?, width: CGFloat) {
        frame = NSRect(x: 0, y: 0, width: width, height: itemHeight)
        statusItem?.length = max(width, 1)
        needsDisplay = true
    }

    func updateViewStatus(enableProxy: Bool) {
        self.enableProxy = enableProxy
        needsDisplay = true
    }

    func updateSpeedLabel(up: Int, down: Int) {
        guard showSpeed else { return }
        self.up = up
        self.down = down
        needsDisplay = true
    }

    func showSpeedContainer(show: Bool) {
        showSpeed = show
        needsDisplay = true
    }
}
