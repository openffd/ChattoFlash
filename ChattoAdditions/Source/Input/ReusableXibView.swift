/*
 The MIT License (MIT)

 Copyright (c) 2015-present Badoo Trading Limited.

 Permission is hereby granted, free of charge, to any person obtaining a copy
 of this software and associated documentation files (the "Software"), to deal
 in the Software without restriction, including without limitation the rights
 to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 copies of the Software, and to permit persons to whom the Software is
 furnished to do so, subject to the following conditions:

 The above copyright notice and this permission notice shall be included in
 all copies or substantial portions of the Software.

 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 THE SOFTWARE.
*/

import UIKit

@objc open class ReusableXibView: UIView {

    func loadViewFromNib() -> UIView {
        let nib = UINib(nibName: type(of: self).nibName(), bundle: Bundle.resources)
        let view = nib.instantiate(withOwner: nil, options: nil).first as! UIView
        return view
    }

    override open func awakeAfter(using aDecoder: NSCoder) -> Any? {
        if subviews.count > 0 {
            return self
        }

        let nib = Bundle.resources.loadNibNamed(type(of: self).nibName(), owner: nil, options: nil)
        guard let loadedView = nib?.first as? UIView else { return nil }
        loadedView.frame = frame
        loadedView.autoresizingMask = autoresizingMask
        loadedView.translatesAutoresizingMaskIntoConstraints = translatesAutoresizingMaskIntoConstraints
        for constraint in constraints {
            let firstItem = constraint.firstItem === self ? loadedView : constraint.firstItem
            let secondItem = constraint.secondItem === self ? loadedView : constraint.secondItem
            let layoutConstraint = NSLayoutConstraint(
                item: firstItem as Any,
                attribute: constraint.firstAttribute,
                relatedBy: constraint.relation,
                toItem: secondItem,
                attribute: constraint.secondAttribute,
                multiplier: constraint.multiplier,
                constant: constraint.constant
            )
            loadedView.addConstraint(layoutConstraint)
        }
        return loadedView
    }

    class func nibName() -> String {
        assert(false, "Must be overriden")
        return ""
    }
}
