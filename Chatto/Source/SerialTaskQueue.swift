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

import Foundation

public typealias TaskClosure = (_ completion: @escaping () -> Void) -> Void

public protocol SerialTaskQueueProtocol {
    var isEmpty: Bool { get }
    var isStopped: Bool { get }
    func addTask(_ task: @escaping TaskClosure)
    func start()
    func stop()
    func flushQueue()
}

public final class SerialTaskQueue: SerialTaskQueueProtocol {
    public private(set) var isBusy = false
    public private(set) var isStopped = true

    private var tasksQueue = [TaskClosure]()

    public init() {}

    public func addTask(_ task: @escaping TaskClosure) {
        tasksQueue.append(task)
        maybeExecuteNextTask()
    }

    public func start() {
        isStopped = false
        maybeExecuteNextTask()
    }

    public func stop() {
        isStopped = true
    }

    public func flushQueue() {
        tasksQueue.removeAll()
    }

    public var isEmpty: Bool {
        tasksQueue.isEmpty
    }

    private func maybeExecuteNextTask() {
        guard !isStopped && !isBusy && !isEmpty else { return }
        let firstTask = tasksQueue.removeFirst()
        isBusy = true
        firstTask { [weak self] in
            self?.isBusy = false
            self?.maybeExecuteNextTask()
        }
    }
}
