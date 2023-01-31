% Volos' Room: Temperature, Humidity and Carbon Monoxide sensors.
% Measure temperature, humidity and CO levels in a room.
% Analyse and present data. IHU MSc IoT project.
%{
	1st reading was on '2022-12-27T10:51:34+02:00'.
	ThingSpeak datetime format, incl. timezone: 'TimeZone','+02:00','Format','uuuu-MM-dd''T''HH:mm:ssXXX'.
	Samples rate (max): 2 samples/minute -> 120 samples/hour -> 720 samples/6 hours -> 2880 samples/day.
	ThingSpeak Channel info:
		readChannelID = 1993597;
		readAPIKey = '';
		TemperatureFieldID = 1;
		HumidityFieldID = 2;
		HeatIndexFieldID = 3;
		COFieldID = 4;
%}
%% Clear all variables
clear all

%% Get data from Thingspeak.
% Channel ID to read data from.
readChannelID = 1993597;
% Channel Read API Key.
readAPIKey = '';
% Get starting datetime. Begin from 00:00 of next day to analyse only full-day readings.
start_datetime = dateshift(datetime('2022-12-27T10:51:34+02:00', 'TimeZone', '+02:00', 'Format', 'uuuu-MM-dd''T''HH:mm:ssXXX'), 'end', 'day');
% Get ending datetime. Stop at today's 00:00 to analyse only full-day readings.
end_datetime = dateshift(datetime('now', 'TimeZone', '+02:00', 'Format', 'uuuu-MM-dd''T''HH:mm:ssXXX'), 'start', 'day');
% Define duration in full days of sensor readings.
dur_days = days(end_datetime - start_datetime);
disp(['Complete daily data available for ', num2str(dur_days), ' days.']);
% List all days to take data from, convert from datetime to strings format.
for i = 1: dur_days+1
	date_strings{i, 1} = char(start_datetime + days(i-1));
end
% Convert days list to datetime format for thingSpeakRead().
datetimes = datetime(date_strings,'TimeZone','+02:00','Format','uuuu-MM-dd''T''HH:mm:ssXXX');
% Get data from ThingSpeak. Iteration is needed to circumvent restrictions.
data = [];
time = [];
days_counter = [];
for i = 1: numel(datetimes)-1
	[data_temp, time_temp] = thingSpeakRead(readChannelID, 'DateRange', [datetimes(i), datetimes(i+1)], 'Fields', (1:4), 'ReadKey', readAPIKey);
	data = vertcat(data, data_temp);
	time = vertcat(time, time_temp);
	days_counter_temp = repelem(i, numel(time_temp));
	days_counter = vertcat(days_counter, transpose(days_counter_temp));
end
disp('Thingspeak data downloaded!');
% Seperate data to their corresponding variable names.
tmprtr = data(:, 1);
hmdt = data(:, 2);
hindx = data(:, 3);
CO = data(:, 4);
% Delete no longer needed vars.
clearvars readChannelID readAPIKey start_datetime end_datetime dur_days date_strings datetimes i data data_temp time_temp days_counter_temp

%% Calculate Dew Point.
% Dew Point calculations, using NOAA's set of constants:
% https://en.wikipedia.org/wiki/Dew_point#Calculating_the_dew_point .
b = 17.67;
c = 243.5;
gamma = log(hmdt/100) + (b * tmprtr) ./ (c + tmprtr);
dewp = (c * gamma) ./ (b - gamma);
% Delete no longer needed vars.
clearvars b c gamma

%% Create table containing datetimes and data.
[hours, minutes, seconds] = hms(time);
time.Format = 'yyyy.MM.dd HH:mm:ss';
timetable = table(time, days_counter, hours, minutes, seconds, tmprtr, hmdt, hindx, dewp, CO, ...
	'VariableNames', {'Datetime', 'DaysCounter', 'Hours', 'Minutes', 'Seconds', 'Temperature', 'Humidity', 'HeatIndex', 'DewPoint', 'CO'});
% Delete no longer needed vars.
clearvars tmprtr hmdt hindx dewp CO hours minutes seconds date time days_counter

%% Check for missing data. If found, clean data and update "timetable".
timetable_chkdata = ismissing(timetable, {'' '.' 'NA' NaN});
timetable_NaNs = timetable(any(timetable_chkdata, 2), :);
if isempty(timetable_NaNs)
	disp('No missing values found!')
else
	disp('Missing values found. Cleaning data before analysis.')
	timetable = table(~any(timetable_chkdata, 2), :);
	disp('Data cleaned, updated "timetable"!')
end
% Delete no longer needed vars.
clearvars timetable_chkdata timetable_NaNs

%% Write table to file for storage and future analysis.
writetable(timetable, 'timetable.csv');

%% Smooth moving average of data.
% Smooth the raw data with local XX-point mean values: 720 points = 6 hours.
timetable.TemperatureSmooth = movmean(timetable.Temperature, 720);
timetable.HumiditySmooth = movmean(timetable.Humidity, 720);
timetable.HeatIndexSmooth = movmean(timetable.HeatIndex, 720);
timetable.DewPointSmooth = movmean(timetable.DewPoint, 720);
timetable.COSmooth = movmean(timetable.CO, 720);
% Fit the data for a trend line.
[p_t, ~, mu_t] = polyfit(datenum(timetable.Datetime), timetable.Temperature, 3);
timetable.TemperatureTrend = polyval(p_t, datenum(timetable.Datetime), [], mu_t);
[p_h, ~, mu_h] = polyfit(datenum(timetable.Datetime), timetable.Humidity, 3);
timetable.HumidityTrend = polyval(p_h, datenum(timetable.Datetime), [], mu_h);
[p_hindx, ~, mu_hindx] = polyfit(datenum(timetable.Datetime), timetable.HeatIndex, 3);
timetable.HeatIndexTrend = polyval(p_hindx, datenum(timetable.Datetime), [], mu_hindx);
[p_d, ~, mu_d] = polyfit(datenum(timetable.Datetime), timetable.DewPoint, 3);
timetable.DewPointTrend = polyval(p_d, datenum(timetable.Datetime), [], mu_d);
[p_CO, ~, mu_CO] = polyfit(datenum(timetable.Datetime), timetable.CO, 3);
timetable.COTrend = polyval(p_CO, datenum(timetable.Datetime), [], mu_CO);
% Delete no longer needed vars.
clearvars p_t mu_t p_h mu_h p_hindx mu_hindx p_d mu_d p_CO mu_CO

%% Correlations table.
to_corrs = table2array(timetable(:, {'Temperature', 'Humidity', 'HeatIndex', 'DewPoint', 'CO'}));
R = corrcoef(to_corrs);		% Correlation coefficients are the same for Smooth data too.
corrs = array2table(R, 'VariableNames', {'Temperature', 'Humidity', 'HeatIndex', 'DewPoint', 'CO'},...
	'RowNames', {'Temperature', 'Humidity', 'HeatIndex', 'DewPoint', 'CO'});
disp(corrs)
% Delete no longer needed vars.
clearvars R to_corrs

%% Group stats analysis.
stats = grpstats(timetable, {'Hours', 'DaysCounter'}, {'min', 'mean', 'max', 'std'},...
	'DataVars', {'Temperature', 'Humidity', 'HeatIndex', 'DewPoint', 'CO'});
summary(stats(:, 4:23))
figure
subplot(2, 2, 1)
hold on
grid on
for i = 1: max(timetable.DaysCounter)
	ii = find(stats{:, 'DaysCounter'} == i);
	plot(stats{ii, 'Hours'}, stats{ii, 'mean_Temperature'}, 'LineWidth', 2)
end
axis tight
xlabel('Hours')
ylabel('Mean Temperature (C)')

subplot(2, 2, 3)
hold on
grid on
for i = 1: max(timetable.DaysCounter)
	ii = find(stats{:, 'DaysCounter'} == i);
	plot(stats{ii, 'Hours'}, stats{ii, 'mean_Humidity'}, 'LineWidth', 2)
end
axis tight
xlabel('Hours')
ylabel('Mean Humidity (%)')

subplot(2, 2, 2)
hold on
grid on
for i = 1: max(timetable.DaysCounter)
	ii = find(stats{:, 'DaysCounter'} == i);
	plot(stats{ii, 'Hours'}, stats{ii, 'std_Temperature'}, 'LineWidth', 2)
end
axis tight
xlabel('Hours')
ylabel('ó Temperature')

subplot(2, 2, 4)
hold on
grid on
for i = 1: max(timetable.DaysCounter)
	ii = find(stats{:, 'DaysCounter'} == i);
	plot(stats{ii, 'Hours'}, stats{ii, 'std_Humidity'}, 'LineWidth', 2)
end
axis tight
xlabel('Hours')
ylabel('ó Humidity')
% Delete no longer needed vars.
clearvars ii

%% Time plots.
% Plot the raw data, smooth data and trend lines.
figure
p = plot(timetable.Datetime, timetable.Temperature, 'g',...
	timetable.Datetime, timetable.TemperatureSmooth, 'm', timetable.Datetime, timetable.TemperatureTrend, 'k');
grid on
p(2).LineWidth = 1.5;
p(3).LineWidth = 2;
xlabel('Date')
ylabel('Temperature (C)')
legend({'Raw Data', 'Smooth Data', 'Trend'}, 'Location', 'southoutside')

figure
p = plot(timetable.Datetime, timetable.Humidity, 'g',...
	timetable.Datetime, timetable.HumiditySmooth, 'm', timetable.Datetime, timetable.HumidityTrend, 'k');
grid on
p(2).LineWidth = 1.5;
p(3).LineWidth = 2;
xlabel('Date')
ylabel('Humidity (%)')
legend({'Raw Data', 'Smooth Data', 'Trend'}, 'Location', 'southoutside')

figure
p = plot(timetable.Datetime, timetable.HeatIndex, 'g',...
	timetable.Datetime, timetable.HeatIndexSmooth, 'm', timetable.Datetime, timetable.HeatIndexTrend, 'k');
grid on
p(2).LineWidth = 1.5;
p(3).LineWidth = 2;
xlabel('Date')
ylabel('Heat Index (C)')
legend({'Raw Data', 'Smooth Data', 'Trend'}, 'Location', 'southoutside')

figure
p = plot(timetable.Datetime, timetable.DewPoint, 'g',...
	timetable.Datetime, timetable.DewPointSmooth, 'm', timetable.Datetime, timetable.DewPointTrend, 'k');
grid on
p(2).LineWidth = 1.5;
p(3).LineWidth = 2;
xlabel('Date')
ylabel('Dew Point (C)')
legend({'Raw Data', 'Smooth Data', 'Trend'}, 'Location', 'southoutside')

figure
p = plot(timetable.Datetime, timetable.CO, 'g',...
	timetable.Datetime, timetable.COSmooth, 'm', timetable.Datetime, timetable.COTrend, 'k');
grid on
p(2).LineWidth = 1.5;
p(3).LineWidth = 2;
xlabel('Date')
ylabel('CO (ppm)')
legend({'Raw Data', 'Smooth Data', 'Trend'}, 'Location', 'southoutside')

% Delete no longer needed vars.
clearvars p

%% Histograms.
% Create histograms.
figure
histogram(timetable.Temperature)
title('Temperature (C) histogram');
grid on

figure
histogram(timetable.Humidity)
title('Humidity (%) histogram');
grid on

figure
histogram(timetable.HeatIndex)
title('Heat Index (C) histogram');
grid on

figure
histogram(timetable.DewPoint)
title('Dew Point (C) histogram');
grid on

figure
histogram(timetable.CO)
title('CO (ppm) histogram');
grid on

%% Heatmaps.
% Calculate bin edges to use in heatmaps.
[bins_hr, edges_hr] = histcounts(timetable.Hours);
[bins_tmprtr, edges_tmprtr] = histcounts(timetable.Temperature);
[bins_hmdt, edges_hmdt] = histcounts(timetable.Humidity);
[bins_CO, edges_CO] = histcounts(timetable.CO);

% Create heatmaps using hist3 function as 2D.
figure
hist3([timetable.Hours timetable.Temperature], 'CdataMode', 'auto', 'Edges', {edges_hr edges_tmprtr})
xlabel('Hours')
ylabel('Temperature (C)')
colorbar
view(2)
axis tight

figure
hist3([timetable.Hours timetable.Humidity], 'CdataMode', 'auto', 'Edges', {edges_hr edges_hmdt})
xlabel('Hours')
ylabel('Humidity (%)')
colorbar
view(2)
axis tight

figure
hist3([timetable.Hours timetable.CO], 'CdataMode', 'auto', 'Edges', {edges_hr edges_CO})
xlabel('Hours')
ylabel('CO (ppm)')
colorbar
view(2)
axis tight

figure
hist3([timetable.Humidity timetable.Temperature], 'CdataMode', 'auto', 'Edges', {edges_hmdt edges_tmprtr})
xlabel('Humidity (%)')
ylabel('Temperature (C)')
colorbar
view(2)
axis tight

% Delete no longer needed vars.
clearvars bins_hr edges_hr bins_tmprtr edges_tmprtr bins_hmdt edges_hmdt bins_CO edges_CO

%% Group plot matrix.
% Create a plot matrix about HeatIndex, DewPoint and CO, grouped by Temperature.
figure
gplotmatrix([timetable.HeatIndex timetable.DewPoint timetable.CO],...
	[], timetable.Temperature, colormap(jet(6)), [], 16, [], 'grpbars', {'HeatIndex','DewPoint', 'CO'})

%% Boxplots.
% Boxplot.
figure
labels = char(datetime(timetable.Datetime, 'Format', 'MMM dd, yyyy'));
boxplot(timetable.Humidity, timetable.DaysCounter, 'labels', labels)
grid on
xlabel('Date')
ylabel('Humidity (%)')

% boxplot([timetable.Temperature timetable.Humidity])
% boxplot([timetable.Temperature timetable.HeatIndex])
% boxplot([timetable.CO timetable.DewPoint])

% Delete no longer needed vars.
clearvars labels

%% KMeans clustering.
data = [timetable.DaysCounter timetable.DewPointSmooth; timetable.DaysCounter timetable.HeatIndexSmooth;...
	timetable.DaysCounter timetable.COSmooth; timetable.DaysCounter timetable.HumiditySmooth];
clusters = 4;
[idx, centroids] = kmeans(data, clusters, 'MaxIter', 100, 'Replicates', 10, 'Distance', 'cityblock');
figure;
hold on
for i = 1: clusters
	plot(data(idx == i, 1), data(idx == i, 2), '.', 'MarkerSize', 12)
end
plot(centroids(:, 1), centroids(:, 2), 'kx', 'MarkerSize', 20, 'LineWidth',3)
legend('Cluster 1', 'Cluster 2', 'Cluster 3', 'Cluster 4', 'Centroids', 'Location', 'best')
title 'Cluster Assignments and Centroids'
hold off
% Delete no longer needed vars.
clearvars centroids clusters data i idx