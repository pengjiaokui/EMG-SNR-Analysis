function emgSNR(csvFile, samplingFrequencyHz)
% EMGSNR Interactively calculate an active-to-rest mean-square ratio in dB.
%
%   emgSNR()                         Select a CSV file from a dialog.
%   emgSNR('recording.csv')          Use the legacy nominal rate (2000 Hz).
%   emgSNR('recording.csv', 1000)    Explicitly specify the recording rate.
%
% INPUT AND PREPROCESSING (same as the legacy script):
%   1. Read the first column with readmatrix, discarding its first matrix row.
%   2. Subtract the overall mean of the retained samples.
%   3. Manually select a rest interval and an active interval using sliders.
%      Each interval is indexed using round(time * samplingFrequencyHz),
%      constrained to the available samples (legacy MATLAB convention).
%
% CALCULATION (UNMODIFIED):
%   noise_power  = mean(restSamples.^2);
%   signal_power = mean(activeSamples.^2);
%   SNR_dB       = 10*log10(signal_power/noise_power);
%
% The analysis measures the ACTIVE/REST MEAN-SQUARE AMPLITUDE RATIO; the
% active interval contains both the muscle signal and background noise.
% It is not an independently separated noise-subtracted signal power.
% The PSD displayed using pwelch is for visual inspection only; it does
% not contribute to the SNR calculation. No additional digital filter
% is applied. Hardware signal conditioning occurs before CSV export.
%
% EXPERIMENTAL WORKFLOW:
%   The first few seconds of each CSV capture are at rest; select about
%   4 s of representative rest as the common noise reference. Select
%   multiple contraction intervals, each adjusted to its actual duration.
%   Record the SNR in dB for each contraction. The final reported number
%   is the ARITHMETIC MEAN of those recorded dB values, performed outside
%   this GUI (the program shows one interval pair at a time).
%
% DATA UNITS AND METADATA:
%   The GUI reports the input CSV units as-is; do not assume that ADC
%   counts represent electrode voltage in mV without a validated scale.
%   The originally used script assumed fs = 2000 Hz, but a separately
%   shared STM32 firmware was configured for a nominal 1000-Hz ADC
%   trigger. Always confirm the acquisition firmware and effective data
%   rate before using the timestamps or PSD frequency axis.
%
% DEFAULT WINDOWS:
%   Rest: 0.5-1.5 s; active: 3-4 s. These are GUI INITIAL VALUES only;
%   they are NOT the fixed experimental window lengths. Adjust manually.
%
% SOFTWARE REQUIREMENTS:
%   MATLAB R2019a or later (readmatrix), Signal Processing Toolbox
%   (pwelch). Exact MATLAB release used in the original experiments is
%   not documented in this repository.
%
% CAUTION:
%   The existing data-import logic unconditionally drops row 1 of the
%   numeric output of readmatrix. Depending on the CSV header/import
%   behavior this may discard the first valid sample. This behavior is
%   retained deliberately to preserve the earlier analysis convention;
%   users must verify it against their CSV export.
%

    % Legacy analysis used a nominal rate of 2000 Hz. This value must be
    % checked against the firmware actually used for the recording. The
    % separately shared STM32 firmware has a nominal 1000-Hz trigger rate.
    if nargin < 2 || isempty(samplingFrequencyHz)
        samplingFrequencyHz = 2000; % legacy default; NOT verified for all files
        warning('emgSNR:VerifySamplingRate', ...
            ['Using the legacy default of 2000 Hz. Verify the actual ' ...
             'sampling rate before interpreting time windows or PSD.']);
    end
    validateattributes(samplingFrequencyHz, {'numeric'}, ...
        {'scalar','real','finite','positive'}, mfilename, 'samplingFrequencyHz');

    if nargin < 1 || isempty(csvFile)
        [fileName, folderName] = uigetfile({'*.csv','CSV files (*.csv)'}, ...
                                          'Select an EMG recording');
        if isequal(fileName,0)
            return;
        end
        csvFile = fullfile(folderName,fileName);
    end

    if ~isfile(csvFile)
        error('emgSNR:FileNotFound', ...
              'The selected CSV file was not found: %s',char(csvFile));
    end

    csvData = readmatrix(csvFile);
    if size(csvData,1) < 3 || size(csvData,2) < 1
        error('emgSNR:InvalidCSV', ...
              'CSV must contain at least three rows and one column.');
    end
    rawEmg = csvData(2:end,1)';
    if any(~isfinite(rawEmg))
        error('emgSNR:NonFiniteData', ...
              'EMG column contains NaN or Inf; check the CSV export.');
    end

    emg = rawEmg - mean(rawEmg);
    sampleCount = numel(emg);
    timeSeconds = (0:sampleCount-1)/samplingFrequencyHz;
    recordDurationSeconds = timeSeconds(end);

    if recordDurationSeconds < 0.2
        error('emgSNR:ShortRecording', ...
              'The recording is too short for interactive window selection.');
    end

    initialRestStart = 0.5;
    initialRestLength = 1.0;
    initialActiveStart = 3.0;
    initialActiveLength = 1.0;

    minWindowSeconds = 0.1;
    maxWindowSeconds = min(5.0,recordDurationSeconds);
    maxStartSeconds = max(0.001,recordDurationSeconds-minWindowSeconds);

    initialRestStart = min(initialRestStart,maxStartSeconds);
    initialActiveStart = min(initialActiveStart,maxStartSeconds);
    initialRestLength = min(initialRestLength,maxWindowSeconds);
    initialActiveLength = min(initialActiveLength,maxWindowSeconds);

    window = figure('Name','EMG SNR | Manual interval selection', ...
                    'NumberTitle','off','Color','w', ...
                    'Position',[180 160 1250 720]);
    waveformAxes = axes('Parent',window, ...
                        'Position',[0.08 0.46 0.86 0.42]);
    plot(waveformAxes,timeSeconds,emg,'k','LineWidth',0.7);
    xlabel(waveformAxes,'Time (s)');
    ylabel(waveformAxes,'EMG amplitude (CSV units)');
    title(waveformAxes,'Recorded EMG after global mean subtraction');
    grid(waveformAxes,'on');
    hold(waveformAxes,'on');

    signalMin = min(emg);
    signalMax = max(emg);
    if signalMin == signalMax
        signalMin = signalMin - 1;
        signalMax = signalMax + 1;
    end
    extraY = 0.05*(signalMax-signalMin);
    windowY = [signalMin-extraY,signalMax+extraY];
    ylim(waveformAxes,windowY);
    xlim(waveformAxes,[0,recordDurationSeconds]);

    restHighlight = patch(waveformAxes,NaN(1,4),NaN(1,4),[0.85 0.35 0.33], ...
                          'FaceAlpha',0.20,'EdgeColor','none');
    activeHighlight = patch(waveformAxes,NaN(1,4),NaN(1,4),[0.25 0.48 0.84], ...
                            'FaceAlpha',0.20,'EdgeColor','none');

    snrLabel = text(waveformAxes,0.02,0.95,'', ...
                    'Units','normalized','VerticalAlignment','top', ...
                    'FontSize',11,'FontWeight','bold', ...
                    'BackgroundColor','white','Margin',5);

    psdAxes = axes('Parent',window, ...
                   'Position',[0.08 0.22 0.86 0.16]);
    [psdValues,frequencyHz] = pwelch(emg,[],[],[],samplingFrequencyHz);
    plot(psdAxes,frequencyHz,10*log10(psdValues), ...
         'Color',[0.25 0.25 0.25],'LineWidth',0.8);
    xlabel(psdAxes,'Frequency (Hz)');
    ylabel(psdAxes,'PSD (10 log_{10} of units^2/Hz)');
    title(psdAxes,'Power spectral density (display only)');
    grid(psdAxes,'on');

    % Sliders control the two independently selected intervals.
    restStartSlider = makeSlider('start',initialRestStart,maxStartSeconds);
    restLengthSlider = makeSlider('length',initialRestLength,maxWindowSeconds);
    activeStartSlider = makeSlider('start',initialActiveStart,maxStartSeconds);
    activeLengthSlider = makeSlider('length',initialActiveLength,maxWindowSeconds);

    createLabel('Rest start (s)',[0.08 0.143 0.14 0.028]);
    set(restStartSlider,'Position',[0.20 0.145 0.26 0.023]);
    createLabel('Rest length (s)',[0.50 0.143 0.14 0.028]);
    set(restLengthSlider,'Position',[0.64 0.145 0.29 0.023]);
    createLabel('Active start (s)',[0.08 0.098 0.14 0.028]);
    set(activeStartSlider,'Position',[0.20 0.100 0.26 0.023]);
    createLabel('Active length (s)',[0.50 0.098 0.14 0.028]);
    set(activeLengthSlider,'Position',[0.64 0.100 0.29 0.023]);

    intervalLabel = uicontrol('Parent',window,'Style','text', ...
        'Units','normalized','Position',[0.08 0.04 0.85 0.035], ...
        'BackgroundColor','w','HorizontalAlignment','left', ...
        'FontSize',10,'String','');

    refreshDisplay();

    function slider = makeSlider(intervalField,initialValue,upperBound)
        if strcmp(intervalField,'start')
            lowerBound = 0;
        else
            lowerBound = minWindowSeconds;
        end
        slider = uicontrol('Parent',window,'Style','slider', ...
            'Units','normalized','Min',lowerBound,'Max',upperBound, ...
            'Value',max(lowerBound,min(initialValue,upperBound)), ...
            'Callback',@refreshDisplay);
    end

    function createLabel(labelText,position)
        uicontrol('Parent',window,'Style','text', ...
            'Units','normalized','Position',position, ...
            'BackgroundColor','w','HorizontalAlignment','left', ...
            'FontSize',10,'String',labelText);
    end

    function refreshDisplay(~,~)
        restStart = restStartSlider.Value;
        restLength = restLengthSlider.Value;
        activeStart = activeStartSlider.Value;
        activeLength = activeLengthSlider.Value;
        restEnd = restStart+restLength;
        activeEnd = activeStart+activeLength;

        restFirst = max(1,round(restStart*samplingFrequencyHz));
        restLast = min(sampleCount,round(restEnd*samplingFrequencyHz));
        activeFirst = max(1,round(activeStart*samplingFrequencyHz));
        activeLast = min(sampleCount,round(activeEnd*samplingFrequencyHz));

        if restLast < restFirst || activeLast < activeFirst
            set(snrLabel,'String','SNR = n/a (invalid interval)');
            return;
        end

        restSamples = emg(restFirst:restLast);
        activeSamples = emg(activeFirst:activeLast);

        noise_power = mean(restSamples.^2);
        signal_power = mean(activeSamples.^2);
        SNR_dB = 10*log10(signal_power/noise_power);

        set(restHighlight,'XData',[restStart restEnd restEnd restStart], ...
            'YData',[windowY(1) windowY(1) windowY(2) windowY(2)]);
        set(activeHighlight,'XData',[activeStart activeEnd activeEnd activeStart], ...
            'YData',[windowY(1) windowY(1) windowY(2) windowY(2)]);
        set(snrLabel,'String',sprintf('SNR = %.2f dB',SNR_dB));
        set(intervalLabel,'String',sprintf( ...
            'Rest: %.2f-%.2f s (%d samples)   |   Active: %.2f-%.2f s (%d samples)', ...
            restStart,restEnd,numel(restSamples),activeStart,activeEnd,numel(activeSamples)));
    end
end
