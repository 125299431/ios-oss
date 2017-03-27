import KsApi
import Library
import LiveStream
import Prelude
import ReactiveSwift
import Result
import UIKit

internal protocol LiveStreamChatViewControllerDelegate: class {
  func liveStreamChatViewController(
    _ controller: LiveStreamChatViewController,
    willPresentMoreMenuViewController moreMenuViewController: LiveStreamContainerMoreMenuViewController)

  func liveStreamChatViewController(
    _ controller: LiveStreamChatViewController,
    willDismissMoreMenuViewController moreMenuViewController: LiveStreamContainerMoreMenuViewController)
}

internal final class LiveStreamChatViewController: UIViewController {

  @IBOutlet private weak var tableView: UITableView!
  @IBOutlet private weak var chatInputViewContainer: UIView!
  @IBOutlet private weak var chatInputViewContainerBottomConstraint: NSLayoutConstraint!
  @IBOutlet private weak var chatInputViewContainerHeightConstraint: NSLayoutConstraint!

  fileprivate let dataSource = LiveStreamChatDataSource()
  fileprivate weak var delegate: LiveStreamChatViewControllerDelegate?
  fileprivate let shareViewModel: ShareViewModelType = ShareViewModel()
  internal let viewModel: LiveStreamChatViewModelType = LiveStreamChatViewModel()

  public static func configuredWith(
    delegate: LiveStreamChatViewControllerDelegate,
    project: Project,
    liveStreamEvent: LiveStreamEvent) ->
    LiveStreamChatViewController {

      let vc = Storyboard.LiveStream.instantiate(LiveStreamChatViewController.self)
      vc.delegate = delegate
      vc.viewModel.inputs.configureWith(project: project, liveStreamEvent: liveStreamEvent, chatHidden: false)
      vc.shareViewModel.inputs.configureWith(shareContext: .liveStream(project, liveStreamEvent))

      return vc
  }

  internal override func viewDidLoad() {
    super.viewDidLoad()

    self.tableView.dataSource = self.dataSource
    self.tableView.keyboardDismissMode = .onDrag
    self.tableView.transform = CGAffineTransform(scaleX: 1, y: -1)

    self.chatInputViewContainer.addSubview(self.liveStreamChatInputView)

    NSLayoutConstraint.activate([
      self.liveStreamChatInputView.leftAnchor.constraint(equalTo: self.chatInputViewContainer.leftAnchor),
      self.liveStreamChatInputView.topAnchor.constraint(equalTo: self.chatInputViewContainer.topAnchor),
      self.liveStreamChatInputView.bottomAnchor.constraint(equalTo: self.chatInputViewContainer.bottomAnchor),
      self.liveStreamChatInputView.rightAnchor.constraint(equalTo: self.chatInputViewContainer.rightAnchor)
      ])

    NotificationCenter.default
      .addObserver(forName: .ksr_sessionStarted, object: nil, queue: nil) { [weak self] _ in
        AppEnvironment.current.currentUser?.liveAuthToken.doIfSome {
          self?.viewModel.inputs.userSessionChanged(
            session: .loggedIn(token: $0)
          )
        }
    }

    NotificationCenter.default
      .addObserver(forName: .ksr_sessionEnded, object: nil, queue: nil) { [weak self] _ in
        self?.viewModel.inputs.userSessionChanged(session: .anonymous)
    }

    NotificationCenter.default
      .addObserver(forName: .UIDeviceOrientationDidChange, object: nil, queue: nil) { [weak self] _ in
        self?.viewModel.inputs.deviceOrientationDidChange(
          orientation: UIApplication.shared.statusBarOrientation
        )
    }

    self.viewModel.inputs.viewDidLoad()
  }

  internal override func bindStyles() {
    super.bindStyles()

    _ = self
      |> baseLiveStreamControllerStyle()
      |> UIViewController.lens.view.backgroundColor .~ .ksr_navy_700

    _ = self.tableView
      |> UITableView.lens.backgroundColor .~ .ksr_navy_700
      |> UITableView.lens.separatorStyle .~ .none
      |> UITableView.lens.rowHeight .~ UITableViewAutomaticDimension
      |> UITableView.lens.estimatedRowHeight .~ 200

    self.tableView.contentInset = .init(topBottom: Styles.grid(1))
  }

  //swiftlint:disable:next function_body_length
  internal override func bindViewModel() {
    super.bindViewModel()

    self.viewModel.outputs.prependChatMessagesToDataSourceAndReload
      .observeForUI()
      .observeValues { [weak self] chatMessages, reload in
        let indexPaths = self?.dataSource.add(chatMessages)
        indexPaths.doIfSome { self?.insert($0, andReload: reload) }
    }

    self.viewModel.outputs.presentLoginToutViewController
      .observeForControllerAction()
      .observeValues { [weak self] in
        self?.presentLoginTout(loginIntent: $0)
    }

    Keyboard.change
      .observeForUI()
      .observeValues { [weak self] change in
        if change.notificationName == .UIKeyboardWillShow {
          self?.chatInputViewContainerBottomConstraint.constant = change.frame.height
        } else {
          self?.chatInputViewContainerBottomConstraint.constant = 0
        }

        UIView.animate(withDuration: change.duration, delay: 0,
                       options: change.options, animations: {
                        self?.view.layoutIfNeeded()
        }, completion: nil)
    }

    self.viewModel.outputs.presentMoreMenuViewController
      .observeForControllerAction()
      .observeValues { [weak self] in
        self?.presentMoreMenu(liveStreamEvent: $0, chatHidden: $1)
    }

    self.shareViewModel.outputs.showShareSheet
      .observeForControllerAction()
      .observeValues { [weak self] in self?.showShareSheet(controller: $0) }

    self.viewModel.outputs.hideChatTableView
      .observeForUI()
      .observeValues { [weak self] in
        self?.tableView.alpha = $0 ? 0 : 1
        self?.liveStreamChatInputView.didSetChatHidden(hidden: $0)
    }

    self.viewModel.outputs.dismissKeyboard
      .observeForUI()
      .observeValues { [weak self] in
        self?.view.endEditing(true)
    }

    self.viewModel.outputs.collapseChatInputView
      .observeForUI()
      .observeValues { [weak self] in
        self?.chatInputViewContainerHeightConstraint.constant = $0 ? 0 : Styles.grid(8)
    }

    self.viewModel.outputs.showErrorAlert
      .observeForUI()
      .observeValues { [weak self] in
        self?.present(UIAlertController.genericError($0), animated: true, completion: nil)
    }
  }

  private lazy var liveStreamChatInputView: LiveStreamChatInputView = {
    let chatInputView = LiveStreamChatInputView.fromNib()
    chatInputView.translatesAutoresizingMaskIntoConstraints = false
    chatInputView.configureWith(delegate: self, chatHidden: false)
    return chatInputView
  }()

  private func showShareSheet(controller: UIActivityViewController) {
    controller.completionWithItemsHandler = { [weak self] activityType, completed, returnedItems, error in
      self?.shareViewModel.inputs.shareActivityCompletion(with: .init(activityType: activityType,
                                                                      completed: completed,
                                                                      returnedItems: returnedItems,
                                                                      activityError: error)
      )
    }

    if UIDevice.current.userInterfaceIdiom == .pad {
      controller.modalPresentationStyle = .popover
      controller.popoverPresentationController?.barButtonItem = self.navigationItem.rightBarButtonItem
      self.present(controller, animated: true, completion: nil)
    } else {
      self.present(controller, animated: true, completion: nil)
    }
  }

  private func insert(_ indexPaths: [IndexPath], andReload reload: Bool) {
    guard reload == false else {
      self.tableView.reloadData()
      return
    }

    self.tableView.beginUpdates()

    if self.tableView.numberOfSections == 0 {
      self.tableView.insertSections(IndexSet(integer: self.dataSource.chatMessagesSection), with: .none)
    }

    self.tableView.insertRows(at: indexPaths, with: .top)

    self.tableView.endUpdates()
  }

  private func presentMoreMenu(liveStreamEvent: LiveStreamEvent, chatHidden: Bool) {
    let vc = LiveStreamContainerMoreMenuViewController.configuredWith(
      liveStreamEvent: liveStreamEvent,
      delegate: self,
      chatHidden: chatHidden
    )
    vc.modalPresentationStyle = .overCurrentContext

    self.delegate?.liveStreamChatViewController(self, willPresentMoreMenuViewController: vc)
    self.present(vc, animated: true, completion: nil)
  }

  fileprivate func presentLoginTout(loginIntent: LoginIntent) {
    let vc = LoginToutViewController.configuredWith(loginIntent: loginIntent)
    let nav = UINavigationController(rootViewController: vc)
    nav.modalPresentationStyle = .formSheet

    self.present(nav, animated: true, completion: nil)
  }
}

extension LiveStreamChatViewController: LiveStreamChatInputViewDelegate {
  func liveStreamChatInputViewDidTapMoreButton(chatInputView: LiveStreamChatInputView) {
    self.viewModel.inputs.moreMenuButtonTapped()
  }

  func liveStreamChatInputView(_ chatInputView: LiveStreamChatInputView, didSendMessage message: String) {
    self.viewModel.inputs.didSendMessage(message: message)
  }

  func liveStreamChatInputViewRequestedLogin(chatInputView: LiveStreamChatInputView) {
    self.viewModel.inputs.chatInputViewRequestedLogin()
  }
}

extension LiveStreamChatViewController: LiveStreamContainerMoreMenuViewControllerDelegate {
  func moreMenuViewControllerWillDismiss(controller: LiveStreamContainerMoreMenuViewController) {
    self.delegate?.liveStreamChatViewController(self, willDismissMoreMenuViewController: controller)
    self.dismiss(animated: true)
  }

  func moreMenuViewControllerDidSetChatHidden(controller: LiveStreamContainerMoreMenuViewController,
                                              hidden: Bool) {
    self.delegate?.liveStreamChatViewController(self, willDismissMoreMenuViewController: controller)
    self.dismiss(animated: true) {
      self.viewModel.inputs.didSetChatHidden(hidden: hidden)
    }
  }

  func moreMenuViewControllerDidShare(controller: LiveStreamContainerMoreMenuViewController,
                                      liveStreamEvent: LiveStreamEvent) {
    self.delegate?.liveStreamChatViewController(self, willDismissMoreMenuViewController: controller)
    self.dismiss(animated: true) {
      self.shareViewModel.inputs.shareButtonTapped()
    }
  }
}
