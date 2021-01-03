//
//  Switcher.m
//  AtemOSC
//
//  Created by Peter Steffey on 12/26/20.
//

#import "Switcher.h"
#import "AppDelegate.h"
#import "Window.h"

@implementation Switcher

@synthesize ipAddress;
@synthesize nickname;
@synthesize feedbackIpAddress;
@synthesize feedbackPort;
@synthesize connectAutomatically;

@synthesize uid;

@synthesize isConnected;
@synthesize connectionStatus;

@synthesize outPort;

@synthesize productName;

@synthesize mMixEffectBlocks;
@synthesize mMixEffectBlockMonitors;

@synthesize keyers;
@synthesize dsk;
@synthesize mMediaPool;
@synthesize mMediaPlayers;
@synthesize mMacroPool;
@synthesize mSuperSource;
@synthesize mMacroControl;
@synthesize mSuperSourceBoxes;
@synthesize mInputs;
@synthesize mSwitcherInputAuxList;

@synthesize mAudioInputs;
@synthesize mAudioMixer;

@synthesize mFairlightAudioSources;
@synthesize mFairlightAudioMixer;

@synthesize mSwitcher;
@synthesize mHyperdecks;

- (void)encodeWithCoder:(NSCoder *)encoder
{
	[encoder encodeObject:self.uid forKey:@"uid"];
	[encoder encodeObject:self.ipAddress forKey:@"ipAddress"];
	[encoder encodeObject:self.feedbackIpAddress forKey:@"feedbackIpAddress"];
	[encoder encodeObject:[[NSNumber numberWithInt: self.feedbackPort] stringValue] forKey:@"feedbackPort"];
	[encoder encodeObject:self.nickname forKey:@"nickname"];
	[encoder encodeObject:[[NSNumber numberWithBool: self.connectAutomatically] stringValue] forKey:@"connectAutomatically"];
}

- (id)initWithCoder:(NSCoder *)decoder
{
	if((self = [self init])) {
		//decode properties, other class vars
		self.uid = [decoder decodeObjectForKey:@"uid"];
		self.ipAddress = [decoder decodeObjectForKey:@"ipAddress"];
		self.feedbackIpAddress = [decoder decodeObjectForKey:@"feedbackIpAddress"];
		self.feedbackPort = [[decoder decodeObjectForKey:@"feedbackPort"] intValue];
		self.nickname = [decoder decodeObjectForKey:@"nickname"];
		self.connectAutomatically = [[decoder decodeObjectForKey:@"connectAutomatically"] boolValue];
	}
	return self;
}

- (id)init
{
	self = [super init];
	
	mSwitcher = NULL;
	mMediaPool = NULL;
	mMacroPool = NULL;
	mSuperSource = NULL;
	mMacroControl = NULL;
	mAudioMixer = NULL;
	
	isConnected = FALSE;
	connectionStatus = @"Not Connected";
	
	connectAutomatically = YES;
	
	return self;
}

- (void)updateFeedback
{
	AppDelegate* appDel = (AppDelegate *) [[NSApplication sharedApplication] delegate];

	if (feedbackIpAddress != nil && feedbackPort > 0)
	{
		if (outPort == nil)
			outPort = [appDel.manager createNewOutputToAddress:feedbackIpAddress atPort:feedbackPort withLabel:@"atemOSC"];
		else
		{
			if (![feedbackIpAddress isEqualToString: [outPort addressString]])
				[outPort setAddressString:feedbackIpAddress];
			if (feedbackPort != [outPort port])
				[outPort setPort:feedbackPort];
		}
	}
}

- (void)connectBMD
{
	[self connectBMD: 5 toIpAddress:[ipAddress copy]];
}
- (void)connectBMD:(int)attemptsRemaining toIpAddress:(NSString *)ipAddress
{
	// Handle case when we run out of attempts or the IP address changes while trying to connect
	if (attemptsRemaining <= 0 || ![ipAddress isEqualToString:[self ipAddress]])
	{
		return;
	}
	
	dispatch_async(dispatch_get_main_queue(), ^{
		// AppDelegate can only be retrieved from main thread
		AppDelegate* appDel = (AppDelegate *) [[NSApplication sharedApplication] delegate];
		Window* window = (Window *) [[NSApplication sharedApplication] mainWindow];

		if (![[self connectionStatus] isEqualToString:@"Connecting"])
		{
			[self setConnectionStatus: @"Connecting"];
			[[window outlineView] reloadItem:self];
		}
		
		dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0ul);
		dispatch_async(queue, ^{
			BMDSwitcherConnectToFailure            failReason;
			
			// Note that ConnectTo() can take several seconds to return, both for success or failure,
			// depending upon hostname resolution and network response times, so it may be best to
			// do this in a separate thread to prevent the main GUI thread blocking.
			HRESULT hr = [appDel mSwitcherDiscovery]->ConnectTo((CFStringRef)ipAddress, &mSwitcher, &failReason);
			if (SUCCEEDED(hr))
			{
				[self switcherConnected];
			}
			else
			{
				NSString* reason;
				BOOL retry = YES;
				switch (failReason)
				{
					case bmdSwitcherConnectToFailureNoResponse:
						reason = @"No response from Switcher";
						break;
					case bmdSwitcherConnectToFailureIncompatibleFirmware:
						reason = @"Switcher has incompatible firmware";
						retry = NO;
						break;
					case bmdSwitcherConnectToFailureCorruptData:
						reason = @"Corrupt data was received during connection attempt";
						break;
					case bmdSwitcherConnectToFailureStateSync:
						reason = @"State synchronisation failed during connection attempt";
						break;
					case bmdSwitcherConnectToFailureStateSyncTimedOut:
						reason = @"State synchronisation timed out during connection attempt";
						break;
					default:
						reason = @"Connection failed for unknown reason";
				}
				if (retry && attemptsRemaining > 1)
				{
					//Delay 2 seconds before everytime connect/reconnect
					//Because the session ID from ATEM switcher will alive not more then 2 seconds
					//After 2 second of idle, the session will be reset then reconnect won't cause error
					double delayInSeconds = 2.0;
					dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, delayInSeconds * NSEC_PER_SEC);
					dispatch_after(popTime, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0),
								   ^(void){
									   //To run in background thread
									   [self connectBMD: attemptsRemaining-1 toIpAddress:ipAddress];
								   });
					[self logMessage:[NSString stringWithFormat:@"%@, retrying %d more times", reason, attemptsRemaining-1]];
				}
				else
				{
					if (retry)
						[self logMessage:@"Failed to connect after 5 attempts"];
					else
						[self logMessage:[NSString stringWithFormat:@"%@", reason]];
					dispatch_async(dispatch_get_main_queue(), ^{
						[self setConnectionStatus:@"Failed to Connect"];
						[[window outlineView] reloadItem:self];
						if ([[window connectionView] switcher] == self)
							[[window connectionView] reload];
					});
				}
			}
		});
	});
}

- (void)switcherConnected
{
	AppDelegate* appDel = (AppDelegate *) [[NSApplication sharedApplication] delegate];

	HRESULT result;

	[self setIsConnected: YES];
	[self setConnectionStatus:@"Connected"];
	
	if ([[NSProcessInfo processInfo] respondsToSelector:@selector(beginActivityWithOptions:reason:)])
	{
		appDel.activity = [[NSProcessInfo processInfo] beginActivityWithOptions:0x00FFFFFF reason:@"receiving OSC messages"];
	}
	
	[self setupMonitors];
	
	[self updateFeedback];
	
	OSCMessage *newMsg = [OSCMessage createWithAddress:@"/atem/led/green"];
	[newMsg addFloat:1.0];
	[outPort sendThisMessage:newMsg];
	newMsg = [OSCMessage createWithAddress:@"/atem/led/red"];
	[newMsg addFloat:0.0];
	[outPort sendThisMessage:newMsg];
	
	NSString* productName = @"N/A";
	if (FAILED(mSwitcher->GetProductName((CFStringRef*)&productName)))
	{
		[self logMessage:@"Could not get switcher product name"];
	}
	
	[self setProductName:productName];
	dispatch_async(dispatch_get_main_queue(), ^{
		Window* window = (Window *) [[NSApplication sharedApplication] mainWindow];
		[[window outlineView] reloadItem:self];
		if ([[window connectionView] switcher] == self)
		{
			[[[window connectionView] productNameTextField] setStringValue:productName];
		}
	});
	
	mSwitcher->AddCallback(mSwitcherMonitor);
	
	// Get the mix effect block iterator
	IBMDSwitcherMixEffectBlockIterator* iterator = NULL;
	if (SUCCEEDED(mSwitcher->CreateIterator(IID_IBMDSwitcherMixEffectBlockIterator, (void**)&iterator)))
	{
		IBMDSwitcherMixEffectBlock* me = NULL;

		// Use the first Mix Effect Block
		int meIndex = 0;
		while (S_OK == iterator->Next(&me))
		{
			mMixEffectBlocks.push_back(me);
			MixEffectBlockMonitor *monitor = new MixEffectBlockMonitor(self, meIndex);
			me->AddCallback(monitor);
			monitor->updateSliderPosition();
			mMonitors.push_back(monitor);
			mMixEffectBlockMonitors.insert(std::make_pair(meIndex, monitor));
			
			//Upstream Keyer
			IBMDSwitcherKeyIterator* keyIterator = NULL;
			IBMDSwitcherKey* key = NULL;
			if (SUCCEEDED(me->CreateIterator(IID_IBMDSwitcherKeyIterator, (void**)&keyIterator)))
			{
				keyers.insert(std::make_pair(meIndex, std::vector<IBMDSwitcherKey*>()));
				while (S_OK == keyIterator->Next(&key))
				{
					keyers[meIndex].push_back(key);
					UpstreamKeyerMonitor *uskMonitor = new UpstreamKeyerMonitor(self, meIndex);
					key->AddCallback(uskMonitor);
					mMonitors.push_back(uskMonitor);
					mUpstreamKeyerMonitors.insert(std::make_pair(meIndex, uskMonitor));
					
					IBMDSwitcherKeyLumaParameters* lumaParams;
					if (SUCCEEDED(key->QueryInterface(IID_IBMDSwitcherKeyLumaParameters, (void**)&lumaParams)))
					{
						UpstreamKeyerLumaParametersMonitor *lumaMonitor = new UpstreamKeyerLumaParametersMonitor(self, meIndex);
						lumaParams->AddCallback(lumaMonitor);
						mMonitors.push_back(lumaMonitor);
						mUpstreamKeyerLumaParametersMonitors.insert(std::make_pair(meIndex, lumaMonitor));
					}
					
					IBMDSwitcherKeyChromaParameters* chromaParams;
					if (SUCCEEDED(key->QueryInterface(IID_IBMDSwitcherKeyChromaParameters, (void**)&chromaParams)))
					{
						UpstreamKeyerChromaParametersMonitor *chromaMonitor = new UpstreamKeyerChromaParametersMonitor(self, meIndex);
						chromaParams->AddCallback(chromaMonitor);
						mMonitors.push_back(chromaMonitor);
						mUpstreamKeyerChromaParametersMonitors.insert(std::make_pair(meIndex, chromaMonitor));
					}
				}
				keyIterator->Release();
				keyIterator = NULL;
			}
			else
			{
				[self logMessage:@"[Debug] Could not create IBMDSwitcherKeyIterator iterator"];
			}
			
			meIndex++;
		}
		
		iterator->Release();
	}
	else
	{
		[self logMessage:@"[Debug] Could not create IBMDSwitcherMixEffectBlockIterator iterator"];
	}
	
	
	// Create an InputMonitor for each input so we can catch any changes to input names
	IBMDSwitcherInputIterator* inputIterator = NULL;
	if (SUCCEEDED(mSwitcher->CreateIterator(IID_IBMDSwitcherInputIterator, (void**)&inputIterator)))
	{
		IBMDSwitcherInput* input = NULL;
		
		// For every input, install a callback to monitor property changes on the input
		while (S_OK == inputIterator->Next(&input))
		{
			BMDSwitcherInputId inputId;
			input->GetInputId(&inputId);
			mInputs.insert(std::make_pair(inputId, input));
			InputMonitor *monitor = new InputMonitor(self, inputId);
			input->AddCallback(monitor);
			mMonitors.push_back(monitor);
			mInputMonitors.insert(std::make_pair(inputId, monitor));
			
			IBMDSwitcherInputAux* auxObj;
			result = input->QueryInterface(IID_IBMDSwitcherInputAux, (void**)&auxObj);
			if (SUCCEEDED(result))
			{
				BMDSwitcherInputId auxId;
				result = auxObj->GetInputSource(&auxId);
				if (SUCCEEDED(result))
				{
					mSwitcherInputAuxList.push_back(auxObj);
				}
			}
		}
		inputIterator->Release();
		inputIterator = NULL;
	}
	else
	{
		[self logMessage:@"[Debug] Could not create IBMDSwitcherInputIterator iterator"];
	}
	
	//Downstream Keyer
	IBMDSwitcherDownstreamKeyIterator* dskIterator = NULL;
	IBMDSwitcherDownstreamKey* downstreamKey = NULL;
	if (SUCCEEDED(mSwitcher->CreateIterator(IID_IBMDSwitcherDownstreamKeyIterator, (void**)&dskIterator)))
	{
		while (S_OK == dskIterator->Next(&downstreamKey))
		{
			dsk.push_back(downstreamKey);
			downstreamKey->AddCallback(mDownstreamKeyerMonitor);
		}
		dskIterator->Release();
		dskIterator = NULL;
	}
	else
	{
		[self logMessage:@"[Debug] Could not create IBMDSwitcherDownstreamKeyIterator iterator"];
	}
	
	// Media Players
	IBMDSwitcherMediaPlayerIterator* mediaPlayerIterator = NULL;
	if (SUCCEEDED(mSwitcher->CreateIterator(IID_IBMDSwitcherMediaPlayerIterator, (void**)&mediaPlayerIterator)))
	{
		IBMDSwitcherMediaPlayer* mediaPlayer = NULL;
		while (S_OK == mediaPlayerIterator->Next(&mediaPlayer))
		{
			mMediaPlayers.push_back(mediaPlayer);
		}
		mediaPlayerIterator->Release();
		mediaPlayerIterator = NULL;
	}
	else
	{
		[self logMessage:@"[Debug] Could not create IBMDSwitcherMediaPlayerIterator iterator"];
	}
	
	// get media pool
	if (FAILED(mSwitcher->QueryInterface(IID_IBMDSwitcherMediaPool, (void**)&mMediaPool)))
	{
		[self logMessage:@"[Debug] Could not get IBMDSwitcherMediaPool interface"];
	}
	
	// get macro pool
	if (SUCCEEDED(mSwitcher->QueryInterface(IID_IBMDSwitcherMacroPool, (void**)&mMacroPool)))
	{
		mMacroPool->AddCallback(mMacroPoolMonitor);
	}
	else
	{
		[self logMessage:@"[Debug] Could not get IID_IBMDSwitcherMacroPool interface"];
	}
	
	// get macro controller
	if (FAILED(mSwitcher->QueryInterface(IID_IBMDSwitcherMacroControl, (void**)&mMacroControl)))
	{
		[self logMessage:@"[Debug] Could not get IID_IBMDSwitcherMacroControl interface"];
	}
	
	// Super source
	if (SUCCEEDED(mSwitcher->CreateIterator(IID_IBMDSwitcherInputSuperSource, (void**)&mSuperSource))) {
		IBMDSwitcherSuperSourceBoxIterator* superSourceIterator = NULL;
		if (SUCCEEDED(mSuperSource->CreateIterator(IID_IBMDSwitcherSuperSourceBoxIterator, (void**)&superSourceIterator)))
		{
			IBMDSwitcherSuperSourceBox* superSourceBox = NULL;
			while (S_OK == superSourceIterator->Next(&superSourceBox))
			{
				mSuperSourceBoxes.push_back(superSourceBox);
			}
			superSourceIterator->Release();
			superSourceIterator = NULL;
		}
		else
		{
			[self logMessage:@"[Debug] Could not create IBMDSwitcherSuperSourceBoxIterator iterator"];
		}
	}
	else
	{
		[self logMessage:@"[Debug] Could not get IBMDSwitcherInputSuperSource interface"];
	}
	
	// Audio Mixer (Output)
	if (SUCCEEDED(mSwitcher->QueryInterface(IID_IBMDSwitcherAudioMixer, (void**)&mAudioMixer)))
	{
		mAudioMixer->AddCallback(mAudioMixerMonitor);
		
		// Audio Inputs
		IBMDSwitcherAudioInputIterator* audioInputIterator = NULL;
		if (SUCCEEDED(mAudioMixer->CreateIterator(IID_IBMDSwitcherAudioInputIterator, (void**)&audioInputIterator)))
		{
			IBMDSwitcherAudioInput* audioInput = NULL;
			while (S_OK == audioInputIterator->Next(&audioInput))
			{
				BMDSwitcherAudioInputId inputId;
				audioInput->GetAudioInputId(&inputId);
				mAudioInputs.insert(std::make_pair(inputId, audioInput));
				AudioInputMonitor *monitor = new AudioInputMonitor(self, inputId);
				audioInput->AddCallback(monitor);
				mMonitors.push_back(monitor);
				mAudioInputMonitors.insert(std::make_pair(inputId, monitor));
			}
			audioInputIterator->Release();
			audioInputIterator = NULL;
		}
		else
		{
			[self logMessage:[NSString stringWithFormat:@"[Debug] Could not create IBMDSwitcherAudioInputIterator iterator. code: %d", HRESULT_CODE(result)]];
		}
	}
	else
	{
		[self logMessage:@"[Debug] Could not get IBMDSwitcherAudioMixer interface (If your switcher supports Fairlight audio, you can ignore this)"];
	}
	
	// Fairlight Audio Mixer
	if (SUCCEEDED(mSwitcher->QueryInterface(IID_IBMDSwitcherFairlightAudioMixer, (void**)&mFairlightAudioMixer))) {
		mFairlightAudioMixer->AddCallback(mFairlightAudioMixerMonitor);
		
		// Audio Inputs
		IBMDSwitcherFairlightAudioInputIterator* audioInputIterator = NULL;
		if (SUCCEEDED(mFairlightAudioMixer->CreateIterator(IID_IBMDSwitcherFairlightAudioInputIterator, (void**)&audioInputIterator)))
		{
			IBMDSwitcherFairlightAudioInput* audioInput = NULL;
			while (S_OK == audioInputIterator->Next(&audioInput))
			{
				// Audio Sources
				IBMDSwitcherFairlightAudioSourceIterator* audioSourceIterator = NULL;
				if (SUCCEEDED(audioInput->CreateIterator(IID_IBMDSwitcherFairlightAudioSourceIterator, (void**)&audioSourceIterator)))
				{
					IBMDSwitcherFairlightAudioSource* audioSource = NULL;
					while (S_OK == audioSourceIterator->Next(&audioSource))
					{
						BMDSwitcherFairlightAudioSourceId sourceId;
						audioSource->GetId(&sourceId);
						mFairlightAudioSources.insert(std::make_pair(sourceId, audioSource));
						FairlightAudioSourceMonitor *monitor = new FairlightAudioSourceMonitor(self, sourceId);
						audioSource->AddCallback(monitor);
						mMonitors.push_back(monitor);
						mFairlightAudioSourceMonitors.insert(std::make_pair(sourceId, monitor));
					}
					audioSourceIterator->Release();
					audioSourceIterator = NULL;
				}
				else
				{
					[self logMessage:[NSString stringWithFormat:@"[Debug] Could not create IBMDSwitcherFairlightAudioSourceIterator iterator. code: %d", HRESULT_CODE(result)]];
				}
			}
			audioInputIterator->Release();
			audioInputIterator = NULL;
		}
		else
		{
			[self logMessage:[NSString stringWithFormat:@"[Debug] Could not create IBMDSwitcherFairlightAudioInputIterator iterator. code: %d", HRESULT_CODE(result)]];
		}
	}
	else
	{
		[self logMessage:@"[Debug] Could not get IBMDSwitcherFairlightAudioMixer interface (If your switcher does not support Fairlight audio, you can ignore this)"];
	}
	
	// Hyperdeck Setup
	IBMDSwitcherHyperDeckIterator* hyperDeckIterator = NULL;
	if (SUCCEEDED(mSwitcher->CreateIterator(IID_IBMDSwitcherHyperDeckIterator, (void**)&hyperDeckIterator)))
	{
		IBMDSwitcherHyperDeck* hyperdeck = NULL;
		while (S_OK == hyperDeckIterator->Next(&hyperdeck))
		{
			BMDSwitcherHyperDeckId hyperdeckId;
			hyperdeck->GetId(&hyperdeckId);
			mHyperdecks.insert(std::make_pair(hyperdeckId, hyperdeck));
			HyperDeckMonitor *monitor = new HyperDeckMonitor(self, hyperdeckId);
			hyperdeck->AddCallback(monitor);
			mMonitors.push_back(monitor);
			mHyperdeckMonitors.insert(std::make_pair(hyperdeckId, monitor));
		}
		hyperDeckIterator->Release();
		hyperDeckIterator = NULL;
	}
	else
	{
		[self logMessage:[NSString stringWithFormat:@"[Debug] Could not create IBMDSwitcherHyperDeckIterator iterator. code: %d", HRESULT_CODE(result)]];
	}
}

- (void)switcherDisconnected
{

	[self setIsConnected: NO];
	
	dispatch_async(dispatch_get_main_queue(), ^{
		Window* window = (Window *) [[NSApplication sharedApplication] mainWindow];
		[[window outlineView] reloadItem:self];

		AppDelegate* appDel = (AppDelegate *) [[NSApplication sharedApplication] delegate];
		if (appDel.activity)
			[[NSProcessInfo processInfo] endActivity:appDel.activity];
		
		appDel.activity = nil;
	});
	
	if (outPort != nil)
	{
		OSCMessage *newMsg = [OSCMessage createWithAddress:@"/atem/led/green"];
		[newMsg addFloat:0.0];
		[outPort sendThisMessage:newMsg];
		newMsg = [OSCMessage createWithAddress:@"/atem/led/red"];
		[newMsg addFloat:1.0];
		[outPort sendThisMessage:newMsg];
	}
	
	[self cleanUpConnection];
	[self connectBMD];
}

- (void)cleanUpConnection
{
	if (mSwitcher)
	{
		mSwitcher->RemoveCallback(mSwitcherMonitor);
		mSwitcher->Release();
		mSwitcher = NULL;
		mSwitcherMonitor = NULL;
	}
	
	int me = 0;
	for (auto const& it : mMixEffectBlocks)
	{
		it->RemoveCallback(mMixEffectBlockMonitors.at(me));
		it->Release();
		
		while (keyers[me].size())
		{
			keyers[me].back()->Release();
			keyers[me].back()->RemoveCallback(mUpstreamKeyerMonitors[me]);
			IBMDSwitcherKeyLumaParameters* lumaParams = nil;
			keyers[me].back()->QueryInterface(IID_IBMDSwitcherKeyLumaParameters, (void**)&lumaParams);
			if (lumaParams != nil)
				lumaParams->RemoveCallback(mUpstreamKeyerLumaParametersMonitors[me]);
			IBMDSwitcherKeyChromaParameters* chromaParams = nil;
			keyers[me].back()->QueryInterface(IID_IBMDSwitcherKeyChromaParameters, (void**)&chromaParams);
			if (chromaParams != nil)
				chromaParams->RemoveCallback(mUpstreamKeyerChromaParametersMonitors[me]);
			keyers[me].pop_back();
		}
		
		me++;
	}
	mMixEffectBlocks.clear();
	mMixEffectBlockMonitors.clear();
	keyers.clear();
	mUpstreamKeyerMonitors.clear();
	mUpstreamKeyerLumaParametersMonitors.clear();
	mUpstreamKeyerChromaParametersMonitors.clear();
	
	for (auto const& it : mInputs)
	{
		it.second->RemoveCallback(mInputMonitors.at(it.first));
		it.second->Release();
	}
	mInputs.clear();
	mInputMonitors.clear();
	
	while (mSwitcherInputAuxList.size())
	{
		mSwitcherInputAuxList.back()->Release();
		mSwitcherInputAuxList.pop_back();
	}

	
	while (dsk.size())
	{
		dsk.back()->RemoveCallback(mDownstreamKeyerMonitor);
		dsk.back()->Release();
		dsk.pop_back();
		mDownstreamKeyerMonitor = NULL;
	}
	
	while (mMediaPlayers.size())
	{
		mMediaPlayers.back()->Release();
		mMediaPlayers.pop_back();
	}
	
	if (mMediaPool)
	{
		mMediaPool->Release();
		mMediaPool = NULL;
	}
	
	if (mMacroPool)
	{
		mMacroPool->RemoveCallback(mMacroPoolMonitor);
		mMacroPool->Release();
		mMacroPool = NULL;
		mMacroPoolMonitor = NULL;
	}
	
	while (mSuperSourceBoxes.size())
	{
		mSuperSourceBoxes.back()->Release();
		mSuperSourceBoxes.pop_back();
	}
	
	if (mAudioMixer)
	{
		mAudioMixer->RemoveCallback(mAudioMixerMonitor);
		mAudioMixer->Release();
		mAudioMixer = NULL;
		mAudioMixerMonitor = NULL;
	}
	
	for (auto const& it : mAudioInputs)
	{
		it.second->RemoveCallback(mAudioInputMonitors.at(it.first));
		it.second->Release();
	}
	mAudioInputs.clear();
	mAudioInputMonitors.clear();
	
	if (mFairlightAudioMixer)
	{
		mFairlightAudioMixer->RemoveCallback(mFairlightAudioMixerMonitor);
		mFairlightAudioMixer->Release();
		mFairlightAudioMixer = NULL;
		mFairlightAudioMixerMonitor = NULL;
	}
	
	for (auto const& it : mFairlightAudioSources)
	{
		it.second->RemoveCallback(mFairlightAudioSourceMonitors.at(it.first));
		it.second->Release();
	}
	mFairlightAudioSources.clear();
	mFairlightAudioSourceMonitors.clear();
	
	for (auto const& it : mHyperdecks)
	{
		it.second->RemoveCallback(mHyperdeckMonitors.at(it.first));
		it.second->Release();
	}
	mHyperdecks.clear();
	mHyperdeckMonitors.clear();
	
	mMonitors.clear();
}

- (void)setupMonitors
{
	mSwitcherMonitor = new SwitcherMonitor(self);
	mMonitors.push_back(mSwitcherMonitor);
	mDownstreamKeyerMonitor = new DownstreamKeyerMonitor(self);
	mMonitors.push_back(mDownstreamKeyerMonitor);
	mMacroPoolMonitor = new MacroPoolMonitor(self);
	mMonitors.push_back(mMacroPoolMonitor);
	mAudioMixerMonitor = new AudioMixerMonitor(self);
	mMonitors.push_back(mAudioMixerMonitor);
	mFairlightAudioMixerMonitor = new FairlightAudioMixerMonitor(self);
	mMonitors.push_back(mFairlightAudioMixerMonitor);
}

// We run this recursively so that we can get the
// delay from each command, and allow for variable
// wait times between sends
- (void)sendStatus
{
	if ([self isConnected])
	{
		[self sendEachStatus:0];
	}
	else
	{
		[self logMessage:@"Cannot send status - Not connected to switcher"];
	}
}

- (void)sendEachStatus:(int)nextMonitor
{
	if (nextMonitor < mMonitors.size()) {
		int delay = mMonitors[nextMonitor]->sendStatus();
		dispatch_after(dispatch_time(DISPATCH_TIME_NOW, delay * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
			[self sendEachStatus:nextMonitor+1];
		});
	}
}

- (void)saveChanges
{
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	NSData *encodedObject = [NSKeyedArchiver archivedDataWithRootObject:self];
	[defaults setObject:encodedObject forKey:[NSString stringWithFormat:@"switcher-%@", self.uid]];
	[defaults synchronize];
}

- (void)logMessage:(NSString *)message
{
	AppDelegate* appDel = (AppDelegate *) [[NSApplication sharedApplication] delegate];
	[appDel logMessage:[NSString stringWithFormat:@"%@: %@", [self ipAddress], message]];
}

@end
