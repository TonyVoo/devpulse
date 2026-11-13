import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_vi.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'gen/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale) : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate = _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates = <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[Locale('en'), Locale('vi')];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'DevPulse'**
  String get appTitle;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// No description provided for @tryAgain.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get tryAgain;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @done.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get done;

  /// No description provided for @all.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get all;

  /// No description provided for @view.
  ///
  /// In en, this message translates to:
  /// **'View'**
  String get view;

  /// No description provided for @loading.
  ///
  /// In en, this message translates to:
  /// **'Loading'**
  String get loading;

  /// No description provided for @loadingEllipsis.
  ///
  /// In en, this message translates to:
  /// **'Loading…'**
  String get loadingEllipsis;

  /// No description provided for @couldNotLoad.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load'**
  String get couldNotLoad;

  /// No description provided for @couldNotLoadThis.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load this'**
  String get couldNotLoadThis;

  /// No description provided for @youreOffline.
  ///
  /// In en, this message translates to:
  /// **'You\'re offline'**
  String get youreOffline;

  /// No description provided for @unknown.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get unknown;

  /// No description provided for @you.
  ///
  /// In en, this message translates to:
  /// **'You'**
  String get you;

  /// No description provided for @someone.
  ///
  /// In en, this message translates to:
  /// **'Someone'**
  String get someone;

  /// No description provided for @demo.
  ///
  /// In en, this message translates to:
  /// **'DEMO'**
  String get demo;

  /// No description provided for @inProgressLabel.
  ///
  /// In en, this message translates to:
  /// **'{label}, in progress'**
  String inProgressLabel(String label);

  /// No description provided for @requestRef.
  ///
  /// In en, this message translates to:
  /// **'Ref: {id}'**
  String requestRef(String id);

  /// No description provided for @pageNotFound.
  ///
  /// In en, this message translates to:
  /// **'Page not found: {path}'**
  String pageNotFound(String path);

  /// No description provided for @justNow.
  ///
  /// In en, this message translates to:
  /// **'just now'**
  String get justNow;

  /// No description provided for @minutesAgo.
  ///
  /// In en, this message translates to:
  /// **'{n}m ago'**
  String minutesAgo(num n);

  /// No description provided for @hoursAgo.
  ///
  /// In en, this message translates to:
  /// **'{n}h ago'**
  String hoursAgo(num n);

  /// No description provided for @daysAgo.
  ///
  /// In en, this message translates to:
  /// **'{n}d ago'**
  String daysAgo(num n);

  /// No description provided for @healthHealthy.
  ///
  /// In en, this message translates to:
  /// **'Healthy'**
  String get healthHealthy;

  /// No description provided for @healthDegraded.
  ///
  /// In en, this message translates to:
  /// **'Degraded'**
  String get healthDegraded;

  /// No description provided for @healthCritical.
  ///
  /// In en, this message translates to:
  /// **'Critical'**
  String get healthCritical;

  /// No description provided for @healthUnknown.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get healthUnknown;

  /// No description provided for @healthSemantics.
  ///
  /// In en, this message translates to:
  /// **'Health: {label}'**
  String healthSemantics(String label);

  /// No description provided for @severitySemantics.
  ///
  /// In en, this message translates to:
  /// **'Severity {n}'**
  String severitySemantics(num n);

  /// No description provided for @statusTriggered.
  ///
  /// In en, this message translates to:
  /// **'Triggered'**
  String get statusTriggered;

  /// No description provided for @statusAcknowledged.
  ///
  /// In en, this message translates to:
  /// **'Acknowledged'**
  String get statusAcknowledged;

  /// No description provided for @statusResolved.
  ///
  /// In en, this message translates to:
  /// **'Resolved'**
  String get statusResolved;

  /// No description provided for @roleOwner.
  ///
  /// In en, this message translates to:
  /// **'Owner'**
  String get roleOwner;

  /// No description provided for @roleAdmin.
  ///
  /// In en, this message translates to:
  /// **'Admin'**
  String get roleAdmin;

  /// No description provided for @roleEngineer.
  ///
  /// In en, this message translates to:
  /// **'Engineer'**
  String get roleEngineer;

  /// No description provided for @roleViewer.
  ///
  /// In en, this message translates to:
  /// **'Viewer'**
  String get roleViewer;

  /// No description provided for @noDataInRange.
  ///
  /// In en, this message translates to:
  /// **'No data in this range'**
  String get noDataInRange;

  /// No description provided for @navOverview.
  ///
  /// In en, this message translates to:
  /// **'Overview'**
  String get navOverview;

  /// No description provided for @navServices.
  ///
  /// In en, this message translates to:
  /// **'Services'**
  String get navServices;

  /// No description provided for @navIncidents.
  ///
  /// In en, this message translates to:
  /// **'Incidents'**
  String get navIncidents;

  /// No description provided for @navCopilot.
  ///
  /// In en, this message translates to:
  /// **'Copilot'**
  String get navCopilot;

  /// No description provided for @navSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get navSettings;

  /// No description provided for @offlineBanner.
  ///
  /// In en, this message translates to:
  /// **'Offline · showing data saved on this device'**
  String get offlineBanner;

  /// No description provided for @pendingChanges.
  ///
  /// In en, this message translates to:
  /// **'{n, plural, =1{1 change waiting to sync} other{{n} changes waiting to sync}}'**
  String pendingChanges(num n);

  /// No description provided for @changeNotApplied.
  ///
  /// In en, this message translates to:
  /// **'A change couldn\'t be applied: {message}'**
  String changeNotApplied(String message);

  /// No description provided for @signIn.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get signIn;

  /// No description provided for @createYourAccount.
  ///
  /// In en, this message translates to:
  /// **'Create your account'**
  String get createYourAccount;

  /// No description provided for @createAccount.
  ///
  /// In en, this message translates to:
  /// **'Create account'**
  String get createAccount;

  /// No description provided for @name.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get name;

  /// No description provided for @workEmail.
  ///
  /// In en, this message translates to:
  /// **'Work email'**
  String get workEmail;

  /// No description provided for @password.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get password;

  /// No description provided for @passwordHint.
  ///
  /// In en, this message translates to:
  /// **'At least 12 characters.'**
  String get passwordHint;

  /// No description provided for @passwordTooShort.
  ///
  /// In en, this message translates to:
  /// **'Use at least 12 characters.'**
  String get passwordTooShort;

  /// No description provided for @invalidEmail.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid email address.'**
  String get invalidEmail;

  /// No description provided for @checkFields.
  ///
  /// In en, this message translates to:
  /// **'Check the highlighted fields.'**
  String get checkFields;

  /// No description provided for @goToRegister.
  ///
  /// In en, this message translates to:
  /// **'New to DevPulse? Create an account'**
  String get goToRegister;

  /// No description provided for @goToLogin.
  ///
  /// In en, this message translates to:
  /// **'Already have an account? Sign in'**
  String get goToLogin;

  /// No description provided for @restoringSession.
  ///
  /// In en, this message translates to:
  /// **'Restoring your session'**
  String get restoringSession;

  /// No description provided for @sessionEnded.
  ///
  /// In en, this message translates to:
  /// **'Your session has ended. Sign in again.'**
  String get sessionEnded;

  /// No description provided for @errNetwork.
  ///
  /// In en, this message translates to:
  /// **'Can\'t reach DevPulse. Check your connection.'**
  String get errNetwork;

  /// No description provided for @errInsecure.
  ///
  /// In en, this message translates to:
  /// **'Can\'t establish a secure connection.'**
  String get errInsecure;

  /// No description provided for @errSlow.
  ///
  /// In en, this message translates to:
  /// **'The response took too long to process.'**
  String get errSlow;

  /// No description provided for @errCancelled.
  ///
  /// In en, this message translates to:
  /// **'Request cancelled'**
  String get errCancelled;

  /// No description provided for @errTooMany.
  ///
  /// In en, this message translates to:
  /// **'Too many attempts. Wait a few minutes and try again.'**
  String get errTooMany;

  /// No description provided for @errServer.
  ///
  /// In en, this message translates to:
  /// **'DevPulse is having trouble right now. Try again shortly.'**
  String get errServer;

  /// No description provided for @errGeneric.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong. Try again.'**
  String get errGeneric;

  /// No description provided for @errInvalidCredentials.
  ///
  /// In en, this message translates to:
  /// **'Email or password is incorrect'**
  String get errInvalidCredentials;

  /// No description provided for @errEmailTaken.
  ///
  /// In en, this message translates to:
  /// **'An account with this email already exists'**
  String get errEmailTaken;

  /// No description provided for @errVersionMismatch.
  ///
  /// In en, this message translates to:
  /// **'This was changed by someone else. Reload and try again.'**
  String get errVersionMismatch;

  /// No description provided for @errInvalidTransition.
  ///
  /// In en, this message translates to:
  /// **'This action isn\'t possible in the incident\'s current status.'**
  String get errInvalidTransition;

  /// No description provided for @errMaxEscalation.
  ///
  /// In en, this message translates to:
  /// **'Already at the highest escalation level.'**
  String get errMaxEscalation;

  /// No description provided for @errSlugTaken.
  ///
  /// In en, this message translates to:
  /// **'That name is already taken. Try another.'**
  String get errSlugTaken;

  /// No description provided for @organizations.
  ///
  /// In en, this message translates to:
  /// **'Organizations'**
  String get organizations;

  /// No description provided for @offlineOrgs.
  ///
  /// In en, this message translates to:
  /// **'You\'re offline. Showing your last known organizations.'**
  String get offlineOrgs;

  /// No description provided for @yourOrganizations.
  ///
  /// In en, this message translates to:
  /// **'Your organizations'**
  String get yourOrganizations;

  /// No description provided for @current.
  ///
  /// In en, this message translates to:
  /// **'Current'**
  String get current;

  /// No description provided for @createFirstOrg.
  ///
  /// In en, this message translates to:
  /// **'Create your first organization'**
  String get createFirstOrg;

  /// No description provided for @createAnotherOrg.
  ///
  /// In en, this message translates to:
  /// **'Create another organization'**
  String get createAnotherOrg;

  /// No description provided for @orgIntro.
  ///
  /// In en, this message translates to:
  /// **'Each organization keeps its own services, incidents and members.'**
  String get orgIntro;

  /// No description provided for @orgName.
  ///
  /// In en, this message translates to:
  /// **'Organization name'**
  String get orgName;

  /// No description provided for @orgNameLength.
  ///
  /// In en, this message translates to:
  /// **'Use 2–120 characters.'**
  String get orgNameLength;

  /// No description provided for @createOrg.
  ///
  /// In en, this message translates to:
  /// **'Create organization'**
  String get createOrg;

  /// No description provided for @noServicesTitle.
  ///
  /// In en, this message translates to:
  /// **'No services connected yet'**
  String get noServicesTitle;

  /// No description provided for @noServicesBody.
  ///
  /// In en, this message translates to:
  /// **'Create a service and an ingest key on the web dashboard, then send telemetry. Health, latency and incidents will show up here.'**
  String get noServicesBody;

  /// No description provided for @criticalOpen.
  ///
  /// In en, this message translates to:
  /// **'{n, plural, =1{1 critical incident open} other{{n} critical incidents open}}'**
  String criticalOpen(num n);

  /// No description provided for @overviewStale.
  ///
  /// In en, this message translates to:
  /// **'Offline · showing the last overview saved on this device'**
  String get overviewStale;

  /// No description provided for @noTelemetryWindow.
  ///
  /// In en, this message translates to:
  /// **'No telemetry received in the selected window — try a longer one.'**
  String get noTelemetryWindow;

  /// No description provided for @requests.
  ///
  /// In en, this message translates to:
  /// **'Requests'**
  String get requests;

  /// No description provided for @errorRate.
  ///
  /// In en, this message translates to:
  /// **'Error rate'**
  String get errorRate;

  /// No description provided for @avgLatency.
  ///
  /// In en, this message translates to:
  /// **'Avg latency'**
  String get avgLatency;

  /// No description provided for @p95Latency.
  ///
  /// In en, this message translates to:
  /// **'p95 latency'**
  String get p95Latency;

  /// No description provided for @approx.
  ///
  /// In en, this message translates to:
  /// **'approx.'**
  String get approx;

  /// No description provided for @requestVolume.
  ///
  /// In en, this message translates to:
  /// **'Request volume'**
  String get requestVolume;

  /// No description provided for @requestVolumeSemantics.
  ///
  /// In en, this message translates to:
  /// **'Request volume chart, {count} requests in this window'**
  String requestVolumeSemantics(String count);

  /// No description provided for @recentIncidents.
  ///
  /// In en, this message translates to:
  /// **'Recent incidents'**
  String get recentIncidents;

  /// No description provided for @noIncidents.
  ///
  /// In en, this message translates to:
  /// **'No incidents'**
  String get noIncidents;

  /// No description provided for @allQuiet.
  ///
  /// In en, this message translates to:
  /// **'All quiet.'**
  String get allQuiet;

  /// No description provided for @recentDeployments.
  ///
  /// In en, this message translates to:
  /// **'Recent deployments'**
  String get recentDeployments;

  /// No description provided for @noDeploymentsYet.
  ///
  /// In en, this message translates to:
  /// **'No deployments yet'**
  String get noDeploymentsYet;

  /// No description provided for @sendFromCi.
  ///
  /// In en, this message translates to:
  /// **'Send them from CI or connect GitHub.'**
  String get sendFromCi;

  /// No description provided for @servicesCount.
  ///
  /// In en, this message translates to:
  /// **'{n, plural, =1{service} other{services}}'**
  String servicesCount(num n);

  /// No description provided for @healthCountSemantics.
  ///
  /// In en, this message translates to:
  /// **'{n} {label}'**
  String healthCountSemantics(num n, String label);

  /// No description provided for @deployments.
  ///
  /// In en, this message translates to:
  /// **'Deployments'**
  String get deployments;

  /// No description provided for @deploymentsEmptyBody.
  ///
  /// In en, this message translates to:
  /// **'Send deployment events from CI with an ingest key, or connect GitHub on the web dashboard.'**
  String get deploymentsEmptyBody;

  /// No description provided for @searchServices.
  ///
  /// In en, this message translates to:
  /// **'Search services'**
  String get searchServices;

  /// No description provided for @noServicesYet.
  ///
  /// In en, this message translates to:
  /// **'No services yet'**
  String get noServicesYet;

  /// No description provided for @noMatchingServices.
  ///
  /// In en, this message translates to:
  /// **'No matching services'**
  String get noMatchingServices;

  /// No description provided for @servicesEmptyBody.
  ///
  /// In en, this message translates to:
  /// **'Add a service and an ingest key from the web dashboard, then its health shows up here.'**
  String get servicesEmptyBody;

  /// No description provided for @tryDifferentSearch.
  ///
  /// In en, this message translates to:
  /// **'Try a different search or clear the filters.'**
  String get tryDifferentSearch;

  /// No description provided for @noDataYet.
  ///
  /// In en, this message translates to:
  /// **'no data yet'**
  String get noDataYet;

  /// No description provided for @noDataYetCap.
  ///
  /// In en, this message translates to:
  /// **'No data yet'**
  String get noDataYetCap;

  /// No description provided for @seenAgo.
  ///
  /// In en, this message translates to:
  /// **'seen {ago}'**
  String seenAgo(String ago);

  /// No description provided for @seenAgoCap.
  ///
  /// In en, this message translates to:
  /// **'Seen {ago}'**
  String seenAgoCap(String ago);

  /// No description provided for @serviceMeta.
  ///
  /// In en, this message translates to:
  /// **'{slug} · {environment} · tier {tier}'**
  String serviceMeta(String slug, String environment, String tier);

  /// No description provided for @service.
  ///
  /// In en, this message translates to:
  /// **'Service'**
  String get service;

  /// No description provided for @metricsError.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load metrics'**
  String get metricsError;

  /// No description provided for @latencyP95.
  ///
  /// In en, this message translates to:
  /// **'Latency p95'**
  String get latencyP95;

  /// No description provided for @cpu.
  ///
  /// In en, this message translates to:
  /// **'CPU'**
  String get cpu;

  /// No description provided for @chartSemantics.
  ///
  /// In en, this message translates to:
  /// **'{title} chart'**
  String chartSemantics(String title);

  /// No description provided for @openIncidents.
  ///
  /// In en, this message translates to:
  /// **'Open incidents'**
  String get openIncidents;

  /// No description provided for @noOpenIncidents.
  ///
  /// In en, this message translates to:
  /// **'No open incidents'**
  String get noOpenIncidents;

  /// No description provided for @noDeploymentsRecorded.
  ///
  /// In en, this message translates to:
  /// **'No deployments recorded'**
  String get noDeploymentsRecorded;

  /// No description provided for @tabOpen.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get tabOpen;

  /// No description provided for @mine.
  ///
  /// In en, this message translates to:
  /// **'Mine'**
  String get mine;

  /// No description provided for @noOpenIncidentsAllClear.
  ///
  /// In en, this message translates to:
  /// **'No open incidents — all clear'**
  String get noOpenIncidentsAllClear;

  /// No description provided for @noIncidentsMatch.
  ///
  /// In en, this message translates to:
  /// **'No incidents match'**
  String get noIncidentsMatch;

  /// No description provided for @incidentsEmptyBody.
  ///
  /// In en, this message translates to:
  /// **'Incidents opened by alert rules or by your team will appear here.'**
  String get incidentsEmptyBody;

  /// No description provided for @tryDifferentFilter.
  ///
  /// In en, this message translates to:
  /// **'Try a different status or severity filter.'**
  String get tryDifferentFilter;

  /// No description provided for @loadOlderFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load — retry'**
  String get loadOlderFailed;

  /// No description provided for @loadOlder.
  ///
  /// In en, this message translates to:
  /// **'Load older incidents'**
  String get loadOlder;

  /// No description provided for @waitingToSync.
  ///
  /// In en, this message translates to:
  /// **'Waiting to sync'**
  String get waitingToSync;

  /// No description provided for @incidentTileSemantics.
  ///
  /// In en, this message translates to:
  /// **'{severity} {key}, {title}, {status}, started {ago}'**
  String incidentTileSemantics(String severity, String key, String title, String status, String ago);

  /// No description provided for @incidentNotFound.
  ///
  /// In en, this message translates to:
  /// **'Incident not found'**
  String get incidentNotFound;

  /// No description provided for @incidentNotFoundBody.
  ///
  /// In en, this message translates to:
  /// **'It may belong to another organization.'**
  String get incidentNotFoundBody;

  /// No description provided for @offlineSaved.
  ///
  /// In en, this message translates to:
  /// **'You\'re offline. The change is saved and will be sent automatically.'**
  String get offlineSaved;

  /// No description provided for @resolveIncidentQ.
  ///
  /// In en, this message translates to:
  /// **'Resolve incident?'**
  String get resolveIncidentQ;

  /// No description provided for @resolutionNoteOptional.
  ///
  /// In en, this message translates to:
  /// **'Resolution note (optional)'**
  String get resolutionNoteOptional;

  /// No description provided for @resolve.
  ///
  /// In en, this message translates to:
  /// **'Resolve'**
  String get resolve;

  /// No description provided for @acknowledge.
  ///
  /// In en, this message translates to:
  /// **'Acknowledge'**
  String get acknowledge;

  /// No description provided for @assignToMe.
  ///
  /// In en, this message translates to:
  /// **'Assign to me'**
  String get assignToMe;

  /// No description provided for @escalate.
  ///
  /// In en, this message translates to:
  /// **'Escalate'**
  String get escalate;

  /// No description provided for @reopen.
  ///
  /// In en, this message translates to:
  /// **'Reopen'**
  String get reopen;

  /// No description provided for @escalatedTimes.
  ///
  /// In en, this message translates to:
  /// **'Escalated ×{n}'**
  String escalatedTimes(num n);

  /// No description provided for @pendingAction.
  ///
  /// In en, this message translates to:
  /// **'Your \"{action}\" is waiting to be sent.'**
  String pendingAction(String action);

  /// No description provided for @startedAgo.
  ///
  /// In en, this message translates to:
  /// **'started {ago}'**
  String startedAgo(String ago);

  /// No description provided for @ownerName.
  ///
  /// In en, this message translates to:
  /// **'owner {name}'**
  String ownerName(String name);

  /// No description provided for @resolution.
  ///
  /// In en, this message translates to:
  /// **'Resolution: {note}'**
  String resolution(String note);

  /// No description provided for @timelineStale.
  ///
  /// In en, this message translates to:
  /// **'Showing the timeline saved on this device.'**
  String get timelineStale;

  /// No description provided for @relatedDeployments.
  ///
  /// In en, this message translates to:
  /// **'Possibly related deployments'**
  String get relatedDeployments;

  /// No description provided for @correlationSemantics.
  ///
  /// In en, this message translates to:
  /// **'Correlation {pct} percent, {kind}'**
  String correlationSemantics(String pct, String kind);

  /// No description provided for @timingOnly.
  ///
  /// In en, this message translates to:
  /// **'Suspected from timing only — not a confirmed cause.'**
  String get timingOnly;

  /// No description provided for @timeline.
  ///
  /// In en, this message translates to:
  /// **'Timeline'**
  String get timeline;

  /// No description provided for @timelineError.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load the timeline'**
  String get timelineError;

  /// No description provided for @comments.
  ///
  /// In en, this message translates to:
  /// **'Comments'**
  String get comments;

  /// No description provided for @noComments.
  ///
  /// In en, this message translates to:
  /// **'No comments yet.'**
  String get noComments;

  /// No description provided for @waitingToSend.
  ///
  /// In en, this message translates to:
  /// **'waiting to send'**
  String get waitingToSend;

  /// No description provided for @addComment.
  ///
  /// In en, this message translates to:
  /// **'Add a comment'**
  String get addComment;

  /// No description provided for @sendComment.
  ///
  /// In en, this message translates to:
  /// **'Send comment'**
  String get sendComment;

  /// No description provided for @correlationSuspected.
  ///
  /// In en, this message translates to:
  /// **'suspected'**
  String get correlationSuspected;

  /// No description provided for @correlationRuledOut.
  ///
  /// In en, this message translates to:
  /// **'ruled out'**
  String get correlationRuledOut;

  /// No description provided for @correlationConfirmed.
  ///
  /// In en, this message translates to:
  /// **'confirmed'**
  String get correlationConfirmed;

  /// No description provided for @conflictNotApplied.
  ///
  /// In en, this message translates to:
  /// **'Your \"{action}\" was not applied: someone else changed this incident first. Showing the latest.'**
  String conflictNotApplied(String action);

  /// No description provided for @showingLatest.
  ///
  /// In en, this message translates to:
  /// **'{message}. Showing the latest.'**
  String showingLatest(String message);

  /// No description provided for @evOpenedByRule.
  ///
  /// In en, this message translates to:
  /// **'Opened by alert “{rule}”'**
  String evOpenedByRule(String rule);

  /// No description provided for @evOpenedBy.
  ///
  /// In en, this message translates to:
  /// **'Opened by {who}'**
  String evOpenedBy(String who);

  /// No description provided for @evAcknowledged.
  ///
  /// In en, this message translates to:
  /// **'{who} acknowledged'**
  String evAcknowledged(String who);

  /// No description provided for @evResolved.
  ///
  /// In en, this message translates to:
  /// **'{who} resolved'**
  String evResolved(String who);

  /// No description provided for @evResolvedNote.
  ///
  /// In en, this message translates to:
  /// **'{who} resolved: {note}'**
  String evResolvedNote(String who, String note);

  /// No description provided for @evReopened.
  ///
  /// In en, this message translates to:
  /// **'{who} reopened'**
  String evReopened(String who);

  /// No description provided for @evAssigned.
  ///
  /// In en, this message translates to:
  /// **'{who} assigned {name}'**
  String evAssigned(String who, String name);

  /// No description provided for @evUnassigned.
  ///
  /// In en, this message translates to:
  /// **'{who} unassigned'**
  String evUnassigned(String who);

  /// No description provided for @evEscalated.
  ///
  /// In en, this message translates to:
  /// **'{who} escalated to level {level}'**
  String evEscalated(String who, String level);

  /// No description provided for @evSeverityChanged.
  ///
  /// In en, this message translates to:
  /// **'{who} changed severity to {severity}'**
  String evSeverityChanged(String who, String severity);

  /// No description provided for @evCommented.
  ///
  /// In en, this message translates to:
  /// **'{who} commented'**
  String evCommented(String who);

  /// No description provided for @evAlertAttached.
  ///
  /// In en, this message translates to:
  /// **'Alert “{rule}” fired again'**
  String evAlertAttached(String rule);

  /// No description provided for @evAlertResolved.
  ///
  /// In en, this message translates to:
  /// **'Alert “{rule}” recovered'**
  String evAlertResolved(String rule);

  /// No description provided for @evDeploymentCorrelated.
  ///
  /// In en, this message translates to:
  /// **'Deployment {version} may be related'**
  String evDeploymentCorrelated(String version);

  /// No description provided for @evProposalApproved.
  ///
  /// In en, this message translates to:
  /// **'{who} approved the AI-proposed step “{description}”'**
  String evProposalApproved(String who, String description);

  /// No description provided for @evProposalRejected.
  ///
  /// In en, this message translates to:
  /// **'{who} rejected the AI-proposed step “{description}”'**
  String evProposalRejected(String who, String description);

  /// No description provided for @evAiReady.
  ///
  /// In en, this message translates to:
  /// **'AI analysis ready'**
  String get evAiReady;

  /// No description provided for @evAiUnavailable.
  ///
  /// In en, this message translates to:
  /// **'AI analysis unavailable'**
  String get evAiUnavailable;

  /// No description provided for @evAiUpdated.
  ///
  /// In en, this message translates to:
  /// **'AI analysis updated'**
  String get evAiUpdated;

  /// No description provided for @aiCopilot.
  ///
  /// In en, this message translates to:
  /// **'AI Copilot'**
  String get aiCopilot;

  /// No description provided for @noInvestigations.
  ///
  /// In en, this message translates to:
  /// **'No investigations yet'**
  String get noInvestigations;

  /// No description provided for @noInvestigationsBody.
  ///
  /// In en, this message translates to:
  /// **'Open an incident and tap \"Investigate with AI\". Copilot gathers metrics, logs and deployments and suggests probable causes with the evidence behind them.'**
  String get noInvestigationsBody;

  /// No description provided for @analysisReady.
  ///
  /// In en, this message translates to:
  /// **'Analysis ready'**
  String get analysisReady;

  /// No description provided for @triggerAuto.
  ///
  /// In en, this message translates to:
  /// **'Automatic'**
  String get triggerAuto;

  /// No description provided for @triggerRequested.
  ///
  /// In en, this message translates to:
  /// **'Requested'**
  String get triggerRequested;

  /// No description provided for @progressQueued.
  ///
  /// In en, this message translates to:
  /// **'Waiting for a worker…'**
  String get progressQueued;

  /// No description provided for @progressCollecting.
  ///
  /// In en, this message translates to:
  /// **'Collecting metrics, logs and deployments…'**
  String get progressCollecting;

  /// No description provided for @progressAnalyzing.
  ///
  /// In en, this message translates to:
  /// **'Analysing the evidence…'**
  String get progressAnalyzing;

  /// No description provided for @aiAnalysis.
  ///
  /// In en, this message translates to:
  /// **'AI analysis'**
  String get aiAnalysis;

  /// No description provided for @runAgain.
  ///
  /// In en, this message translates to:
  /// **'Run again'**
  String get runAgain;

  /// No description provided for @analysisStale.
  ///
  /// In en, this message translates to:
  /// **'Showing the analysis saved on this device.'**
  String get analysisStale;

  /// No description provided for @aiLoadError.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load the AI analysis'**
  String get aiLoadError;

  /// No description provided for @aiIntro.
  ///
  /// In en, this message translates to:
  /// **'Copilot reads this incident\'s metrics, logs, deployments and similar past incidents, then suggests probable causes, each with the evidence behind it.'**
  String get aiIntro;

  /// No description provided for @investigateWithAi.
  ///
  /// In en, this message translates to:
  /// **'Investigate with AI'**
  String get investigateWithAi;

  /// No description provided for @investigateOffline.
  ///
  /// In en, this message translates to:
  /// **'Investigate (needs a connection)'**
  String get investigateOffline;

  /// No description provided for @analysisUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Analysis unavailable'**
  String get analysisUnavailable;

  /// No description provided for @actionsUnaffected.
  ///
  /// In en, this message translates to:
  /// **'Incident actions are not affected.'**
  String get actionsUnaffected;

  /// No description provided for @hypotheses.
  ///
  /// In en, this message translates to:
  /// **'Hypotheses — not confirmed · {ago}'**
  String hypotheses(String ago);

  /// No description provided for @probableCauses.
  ///
  /// In en, this message translates to:
  /// **'Probable causes'**
  String get probableCauses;

  /// No description provided for @nextSteps.
  ///
  /// In en, this message translates to:
  /// **'Recommended next steps'**
  String get nextSteps;

  /// No description provided for @couldNotSee.
  ///
  /// In en, this message translates to:
  /// **'What DevPulse could not see'**
  String get couldNotSee;

  /// No description provided for @adjusted.
  ///
  /// In en, this message translates to:
  /// **'Adjusted: {text}'**
  String adjusted(String text);

  /// No description provided for @askFollowUp.
  ///
  /// In en, this message translates to:
  /// **'Ask a follow-up'**
  String get askFollowUp;

  /// No description provided for @helpful.
  ///
  /// In en, this message translates to:
  /// **'Helpful'**
  String get helpful;

  /// No description provided for @notHelpful.
  ///
  /// In en, this message translates to:
  /// **'Not helpful'**
  String get notHelpful;

  /// No description provided for @feedbackThanks.
  ///
  /// In en, this message translates to:
  /// **'Thanks, your feedback helps tune the investigator.'**
  String get feedbackThanks;

  /// No description provided for @verify.
  ///
  /// In en, this message translates to:
  /// **'Verify: {how}'**
  String verify(String how);

  /// No description provided for @approvedNotRun.
  ///
  /// In en, this message translates to:
  /// **'· Approved (not executed by DevPulse)'**
  String get approvedNotRun;

  /// No description provided for @rejected.
  ///
  /// In en, this message translates to:
  /// **'· Rejected'**
  String get rejected;

  /// No description provided for @approve.
  ///
  /// In en, this message translates to:
  /// **'Approve'**
  String get approve;

  /// No description provided for @reject.
  ///
  /// In en, this message translates to:
  /// **'Reject'**
  String get reject;

  /// No description provided for @adminMustDecide.
  ///
  /// In en, this message translates to:
  /// **'An admin must decide on destructive actions.'**
  String get adminMustDecide;

  /// No description provided for @approveQ.
  ///
  /// In en, this message translates to:
  /// **'Approve this action?'**
  String get approveQ;

  /// No description provided for @approveBody.
  ///
  /// In en, this message translates to:
  /// **'“{description}”\n\nApproving records your decision on the incident. DevPulse does not run it: your team carries it out.'**
  String approveBody(String description);

  /// No description provided for @confidenceHigh.
  ///
  /// In en, this message translates to:
  /// **'high'**
  String get confidenceHigh;

  /// No description provided for @confidenceMedium.
  ///
  /// In en, this message translates to:
  /// **'medium'**
  String get confidenceMedium;

  /// No description provided for @confidenceLow.
  ///
  /// In en, this message translates to:
  /// **'low'**
  String get confidenceLow;

  /// No description provided for @confidenceSemantics.
  ///
  /// In en, this message translates to:
  /// **'{label} confidence, {pct} percent'**
  String confidenceSemantics(String label, String pct);

  /// No description provided for @riskReadOnly.
  ///
  /// In en, this message translates to:
  /// **'Read-only'**
  String get riskReadOnly;

  /// No description provided for @riskDestructive.
  ///
  /// In en, this message translates to:
  /// **'Destructive · admin approval'**
  String get riskDestructive;

  /// No description provided for @riskSensitive.
  ///
  /// In en, this message translates to:
  /// **'Changes a system · needs approval'**
  String get riskSensitive;

  /// No description provided for @demoAnalyzer.
  ///
  /// In en, this message translates to:
  /// **'DEMO ANALYZER · NOT AN LLM'**
  String get demoAnalyzer;

  /// No description provided for @against.
  ///
  /// In en, this message translates to:
  /// **'{ref} (against)'**
  String against(String ref);

  /// No description provided for @evidenceComputed.
  ///
  /// In en, this message translates to:
  /// **'Computed by DevPulse from stored {kind} data, not by the AI.'**
  String evidenceComputed(String kind);

  /// No description provided for @evidenceSource.
  ///
  /// In en, this message translates to:
  /// **'Source: {source}'**
  String evidenceSource(String source);

  /// No description provided for @askCopilot.
  ///
  /// In en, this message translates to:
  /// **'Ask Copilot'**
  String get askCopilot;

  /// No description provided for @askHint.
  ///
  /// In en, this message translates to:
  /// **'Ask about this incident, e.g. \"When did errors start?\" or \"Was this seen before?\". Answers cite evidence; Copilot can only read data, never change anything.'**
  String get askHint;

  /// No description provided for @lookingIntoIt.
  ///
  /// In en, this message translates to:
  /// **'Looking into it…'**
  String get lookingIntoIt;

  /// No description provided for @questionHint.
  ///
  /// In en, this message translates to:
  /// **'Ask a follow-up question'**
  String get questionHint;

  /// No description provided for @needsConnection.
  ///
  /// In en, this message translates to:
  /// **'Needs a connection'**
  String get needsConnection;

  /// No description provided for @sendQuestion.
  ///
  /// In en, this message translates to:
  /// **'Send question'**
  String get sendQuestion;

  /// No description provided for @lookedUp.
  ///
  /// In en, this message translates to:
  /// **'Looked up {tool} → {refs}'**
  String lookedUp(String tool, String refs);

  /// No description provided for @aiDisabled.
  ///
  /// In en, this message translates to:
  /// **'AI analysis is turned off for this organization. An admin can enable it in Settings → AI on the web.'**
  String get aiDisabled;

  /// No description provided for @aiBudget.
  ///
  /// In en, this message translates to:
  /// **'This month\'s AI budget is used up. An admin can raise it on the web.'**
  String get aiBudget;

  /// No description provided for @aiUnconfigured.
  ///
  /// In en, this message translates to:
  /// **'No AI provider is configured on this DevPulse server.'**
  String get aiUnconfigured;

  /// No description provided for @aiNoEvidence.
  ///
  /// In en, this message translates to:
  /// **'DevPulse has no telemetry for this incident, so there\'s nothing to analyse.'**
  String get aiNoEvidence;

  /// No description provided for @aiInvalidOutput.
  ///
  /// In en, this message translates to:
  /// **'The AI\'s answer failed validation and was discarded.'**
  String get aiInvalidOutput;

  /// No description provided for @aiRefused.
  ///
  /// In en, this message translates to:
  /// **'The AI model declined to analyse this incident.'**
  String get aiRefused;

  /// No description provided for @aiTimeout.
  ///
  /// In en, this message translates to:
  /// **'The analysis took too long.'**
  String get aiTimeout;

  /// No description provided for @aiUnavailable.
  ///
  /// In en, this message translates to:
  /// **'The AI provider is unavailable right now. Try again in a minute.'**
  String get aiUnavailable;

  /// No description provided for @aiStale.
  ///
  /// In en, this message translates to:
  /// **'The analysis was interrupted.'**
  String get aiStale;

  /// No description provided for @aiAlreadyRunning.
  ///
  /// In en, this message translates to:
  /// **'An analysis is already running for this incident.'**
  String get aiAlreadyRunning;

  /// No description provided for @aiFailed.
  ///
  /// In en, this message translates to:
  /// **'The analysis failed.'**
  String get aiFailed;

  /// No description provided for @signOutQ.
  ///
  /// In en, this message translates to:
  /// **'Sign out?'**
  String get signOutQ;

  /// No description provided for @signOutBody.
  ///
  /// In en, this message translates to:
  /// **'Data saved on this device for your account will be removed.'**
  String get signOutBody;

  /// No description provided for @signOut.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get signOut;

  /// No description provided for @profile.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get profile;

  /// No description provided for @organization.
  ///
  /// In en, this message translates to:
  /// **'Organization'**
  String get organization;

  /// No description provided for @noneSelected.
  ///
  /// In en, this message translates to:
  /// **'None selected'**
  String get noneSelected;

  /// No description provided for @yourRole.
  ///
  /// In en, this message translates to:
  /// **'Your role: {role}'**
  String yourRole(String role);

  /// No description provided for @appearance.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get appearance;

  /// No description provided for @themeSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get themeSystem;

  /// No description provided for @themeDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get themeDark;

  /// No description provided for @themeLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get themeLight;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @languageSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get languageSystem;

  /// No description provided for @account.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get account;

  /// No description provided for @settingsFooter.
  ///
  /// In en, this message translates to:
  /// **'Notification preferences and security settings arrive with push notifications (Phase 3).'**
  String get settingsFooter;
}

class _AppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) => <String>['en', 'vi'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'vi':
      return AppLocalizationsVi();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
