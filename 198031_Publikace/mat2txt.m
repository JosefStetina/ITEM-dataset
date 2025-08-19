function mat2txt(inputMatFile, outputTxtFile, opts)
% MAT2TXT  Převod .mat -> čitelný .txt (+ volitelně CSV listy)
% mat2txt('soubor.mat','vystup.txt');                % základ
% mat2txt('soubor.mat','vystup.txt', struct('writeCsvPerLeaf',true,'csvFolder',"csv"));

if nargin < 3, opts = struct; end
if ~isfield(opts,'writeCsvPerLeaf'), opts.writeCsvPerLeaf = false; end
if ~isfield(opts,'csvFolder'),       opts.csvFolder       = "csv"; end
if ~isfield(opts,'numericPrecision'),opts.numericPrecision= 6; end
if ~isfield(opts,'maxPreview'),      opts.maxPreview      = 20; end % max řádků pro text náhled v .txt

S = load(inputMatFile);
[fid, msg] = fopen(outputTxtFile, 'w');
assert(fid~=-1, "Nelze otevřít výstupní soubor: %s", msg);

fprintf(fid, "Zdroj: %s\nVygenerováno: %s\n\n", inputMatFile, datestr(now));

if opts.writeCsvPerLeaf
    if ~exist(opts.csvFolder, "dir")
        mkdir(opts.csvFolder);
    end
    fprintf(fid, "Pozn.: Numerická/řetězcová pole jsou také exportována do CSV ve složce: %s\n\n", opts.csvFolder);
end

vars = fieldnames(S);
for i = 1:numel(vars)
    name = vars{i};
    fprintf(fid, "===== %s =====\n", name);
    dumpVar(fid, S.(name), name, 0, opts);
    fprintf(fid, "\n");
end

fclose(fid);
fprintf("Hotovo. Uloženo do: %s\n", outputTxtFile);
if opts.writeCsvPerLeaf
    fprintf("CSV soubory ve složce: %s\n", opts.csvFolder);
end
end

% ---------- Pomocné funkce ----------

function dumpVar(fid, v, path, indent, opts)
pad = repmat(' ',1, 2*indent);  % odsazení
cls = class(v);
sz  = size(v);

% Krátký řádek s typem a rozměrem
fprintf(fid, "%s[%s] size=%s\n", pad, cls, mat2str(sz));

% Podle typu:
if istable(v)
    % Tabulka – vytisknout hlavičky a pár řádků náhledu
    fprintf(fid, "%s<tabulka s %d řádky a %d sloupci>\n", pad, height(v), width(v));
    headN = min(opts.maxPreview, height(v));
    if headN>0
        T = v(1:headN,:);
        printTablePreview(fid, T, pad);
    end
    maybeWriteCsv(fid, v, path, opts);  % export celé tabulky do CSV
elseif isstruct(v)
    % struct (může být pole structů)
    if numel(v) > 1
        for k = 1:numel(v)
            fprintf(fid, "%s- (%d/%d)\n", pad, k, numel(v));
            dumpVar(fid, v(k), sprintf('%s(%d)', path, k), indent+1, opts);
        end
    else
        flds = fieldnames(v);
        for j = 1:numel(flds)
            f = flds{j};
            fprintf(fid, "%s.%s:\n", pad, f);
            dumpVar(fid, v.(f), sprintf('%s.%s', path, f), indent+1, opts);
        end
    end
elseif iscell(v)
    % buňky – projít položky
    for k = 1:numel(v)
        fprintf(fid, "%s{%d}:\n", pad, k);
        dumpVar(fid, v{k}, sprintf('%s{%d}', path, k), indent+1, opts);
    end
elseif isnumeric(v) || islogical(v) || isstring(v) || ischar(v) || isdatetime(v) || isduration(v) || iscategorical(v)
    % list – lze uložit do CSV + náhled do txt
    previewAndCsv(fid, v, path, pad, opts);
else
    % Jiné typy – stručná informace
    fprintf(fid, "%s<neznamy/komplexni typ '%s' – ukládám pouze informaci o velikosti>\n", pad, class(v));
end
end

function previewAndCsv(fid, v, path, pad, opts)
% vytisknout krátký náhled do TXT
if isnumeric(v) || islogical(v)
    printMatrixPreview(fid, v, pad, opts.maxPreview, opts.numericPrecision);
elseif isstring(v) || ischar(v) || iscategorical(v)
    printTextArrayPreview(fid, v, pad, opts.maxPreview);
elseif isdatetime(v) || isduration(v)
    printTextArrayPreview(fid, string(v), pad, opts.maxPreview);
end
% a případně uložit celé do CSV
maybeWriteCsv(fid, v, path, opts);
end

function maybeWriteCsv(~, v, path, opts)
if ~opts.writeCsvPerLeaf, return; end
fname = sanitizePath(path) + ".csv";
full  = fullfile(opts.csvFolder, fname);

% převod na tabulkovou formu pro writetable
T = valueToTable(v);
writetable(T, full);
end

function T = valueToTable(v)
% Konverze různých typů na tabulku (sloupce)
if istable(v)
    T = v;
elseif isnumeric(v) || islogical(v)
    T = array2table(v);
elseif isstring(v) || ischar(v)
    s = string(v);
    T = table(s, 'VariableNames', {'text'});
elseif iscategorical(v)
    T = table(string(v), 'VariableNames', {'categorical'});
elseif isdatetime(v) || isduration(v)
    T = table(string(v), 'VariableNames', {'time'});
else
    % fallback – serializace do stringu
    T = table(stringify(v), 'VariableNames', {'value'});
end
end

function s = sanitizePath(p)
% povolit jen [A-Za-z0-9._-], zbytek nahradit podtržítkem
s = regexprep(p, '[^A-Za-z0-9._-]', '_');
% zkrať extrémně dlouhé názvy
if strlength(s) > 150
    s = extractBefore(s, 151);
end
end

function printMatrixPreview(fid, M, pad, maxRows, prec)
[r, c] = size(M);
show = min(r, maxRows);
fmtRow = [repmat(sprintf('%%.%df\t', prec), 1, c-1), sprintf('%%.%df\\n', prec)];
for i = 1:show
    fprintf(fid, "%s", pad);
    fprintf(fid, fmtRow, M(i, :));
end
if r > show
    fprintf(fid, "%s... (%d/%d řádků zobrazeno)\n", pad, show, r);
end
end

function printTextArrayPreview(fid, A, pad, maxRows)
A = string(A);
[r, c] = size(A);
show = min(r, maxRows);
for i = 1:show
    fprintf(fid, "%s", pad);
    % spojit sloupce tabem
    line = strjoin(A(i, :), "\t");
    fprintf(fid, "%s\n", line);
end
if r > show
    fprintf(fid, "%s... (%d/%d řádků zobrazeno)\n", pad, show, r);
end
end

function printTablePreview(fid, T, pad)
vn = T.Properties.VariableNames;
fprintf(fid, "%s", pad); fprintf(fid, "%s\n", strjoin(vn, "\t"));
for i = 1:height(T)
    row = strings(1, width(T));
    for j = 1:width(T)
        val = T{i,j};
        if iscell(val), val = val{1}; end
        row(j) = stringify(val);
    end
    fprintf(fid, "%s%s\n", pad, strjoin(row, "\t"));
end
end

function s = stringify(x)
try
    if isstring(x) || ischar(x), s = string(x);
    elseif isnumeric(x) || islogical(x), s = string(x);
    elseif isdatetime(x) || isduration(x), s = string(x);
    elseif iscategorical(x), s = string(x);
    else, s = string(evalc('disp(x)')); % nouzová serializace
    end
catch
    s = "<nepřeveditelné>";
end
end
