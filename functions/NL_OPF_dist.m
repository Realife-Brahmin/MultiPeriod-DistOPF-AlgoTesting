function [x, B0Vals_pu_Area, ...
    macroIterationPLosses, macroIterationQLosses, macroIterationPSaves, macroItr, ...
    time_dist, N_Area, m_Area, nDER_Area, nBatt_Area, busDataTable_pu_Area, ...
    branchDataTable_Area] = ...
    ...
    NL_OPF_dist(v_parent_Area, S_connection_Area, B0Vals_pu_Area, ...
    Area, isLeaf_Area, isRoot_Area, numChildAreas_Area, numAreas, ...
    macroIterationPLosses, macroIterationQLosses, macroIterationPSaves, ...
    lambdaVals, pvCoeffVals, time_dist, t, macroItr, ...
    CB_FullTable, T, varargin)
    
 % Default values for optional arguments
    verbose = false;
    logging_Aeq_beq = false;
    logging = false;
    CVR = [0; 0];
    V_max = 1.05;
    V_min = 0.95;
    Qref_DER = 0.00;
    Vref_DER = 1.00;
    delta_t = 0.25;
    etta_D = 0.95;
    etta_C = 0.95;
    chargeToPowerRatio = 4;
    soc_min = 0.30;
    soc_max = 0.95;

    saveToFile = false;
    strArea = convert2doubleDigits(Area);
    fileExtension = ".txt";
    systemName = "ieee123";
    saveLocationName = "logfiles/";
    fileOpenedFlag_Aeq_beq = false;

    % Process optional arguments
    numArgs = numel(varargin);

    if mod(numArgs, 2) ~= 0
        error('Optional arguments must be specified as name-value pairs.');
    end
    
    validArgs = ["verbose", "logging", "logging_Aeq_beq", "systemName", ...
        "CVR", "V_max", "V_min", "saveToFile", "saveLocation", "Qref_DER", ...
        "Vref_DER", "fileExtension", "delta_t", "etta_C", "etta_D", ...
        "chargeToPowerRatio", "soc_min", "soc_max"];
    
    for i = 1:2:numArgs
        argName = varargin{i};
        argValue = varargin{i+1};
        
        if ~ischar(argName) || ~any(argName == validArgs)
            error('Invalid optional argument name.');
        end
        
        switch argName
            case "verbose"
                verbose = argValue;
            case "logging"
                logging = argValue;
            case "logging_Aeq_beq"
                logging_Aeq_beq = argValue;
            case "systemName"
                systemName = argValue;
            case "CVR"
                CVR = argValue;
            case "V_max"
                V_max = argValue;
            case "V_min"
                V_min = argValue;
            case 'saveToFile'
                saveToFile = argValue;
            case 'saveLocation'
                saveLocationName = argValue;
            case 'Vref_DER'
                Vref_DER = argValue;
            case 'Qref_DER'
                Qref_DER = argValue;
            case 'delta_t'
                delta_t = argValue;
            case 'etta_C'
                etta_C = argValue;
            case 'etta_D'
                etta_D = argValue;
            case "chargeToPowerRatio"
                chargeToPowerRatio = argValue;
            case "soc_min"
                soc_min = argValue;
            case "soc_max"
                soc_max = argValue;
        end
    end
    
    saveLocationFilename = strcat(saveLocationName , systemName, "/numAreas_", num2str(numAreas), "/optimizationLogs", fileExtension);
    saveLocationFilename_Aeq_beq = strcat(saveLocationName , systemName, "/numAreas_", num2str(numAreas), "/Aeq_beq_area", strArea, fileExtension);

    if macroItr ~= 1
        logging_Aeq_beq = false;
    end

    if logging_Aeq_beq && saveToFile && macroItr == 1 && Area == 2
        fileOpenedFlag_Aeq_beq = true;
        fid_Aeq_beq = fopen(saveLocationFilename_Aeq_beq, 'w');  % Open file for writing
    else
        logging_Aeq_beq = false;
        fid_Aeq_beq = 1;
    end
    
    if logging && verbose
        error("Kindly specify ONLY one of the following arguments as true: verbose and logging.")
    elseif logging && ~verbose
        fileOpenedFlag = true;
        if t == 1
            fid = fopen(saveLocationFilename, 'w');
        else
            fid = fopen(saveLocationFilename, 'a');
        end
    elseif ~logging
        logging = verbose;
        fid = 1;
    end

    [busDataTable_pu_Area, branchDataTable_Area, edgeMatrix_Area, R_Area, X_Area] ...
        = extractAreaElectricalParameters(Area, t, macroItr, isRoot_Area, systemName, numAreas, CB_FullTable, numChildAreas_Area, 'verbose', verbose, 'logging', logging, 'displayNetworkGraphs', false);
    
    N_Area = length(busDataTable_pu_Area.bus);
    m_Area = length(branchDataTable_Area.fb);
    fb_Area = branchDataTable_Area.fb;
    tb_Area = branchDataTable_Area.tb;
    P_L_Area = busDataTable_pu_Area.P_L;
    Q_L_Area = busDataTable_pu_Area.Q_L;
    Q_C_Area = busDataTable_pu_Area.Q_C;
    P_der_Area = busDataTable_pu_Area.P_der;
    S_der_Area = busDataTable_pu_Area.S_der;
    S_battMax_Area = S_der_Area;
    P_battMax_Area = P_der_Area;

    Emax_batt_Area = chargeToPowerRatio.*P_battMax_Area;

% Update the Parent Complex Power Vector with values from interconnection. 

    numChildAreas = size(S_connection_Area, 1); %could even be zero for a child-less area
    
    for j = 1:numChildAreas %nodes are numbered such that the last numChildAreas nodes are actually the interconnection nodes too.
        %The load of parent area at the node of interconnection is
        %basically the interconnection area power
        P_L_Area(end-j+1) = real(S_connection_Area(end-j+1));                 %in PU
        Q_L_Area(end-j+1) = imag(S_connection_Area(end-j+1));     
    end
    
    % DER Configuration:
    busesWithDERs_Area = find(S_der_Area); %all nnz element indices
    nDER_Area = length(busesWithDERs_Area);
    busesWithBatts_Area = find(S_battMax_Area);
    nBatt_Area = length(busesWithBatts_Area);
    B0Vals_pu_Area = reshape(B0Vals_pu_Area(1:nBatt_Area), nBatt_Area, 1);

    myfprintf(logging_Aeq_beq, fid_Aeq_beq, strcat("Number of DERs in Area ", num2str(Area), " : ", num2str(nDER_Area), ".\n") );
    myfprintf(logging_Aeq_beq, fid_Aeq_beq, strcat("Number of Batteries in Area ", num2str(Area), " : ", num2str(nBatt_Area), ".\n") );

    myfprintf(logging, fid, strcat("Number of DERs in Area ", num2str(Area), " : ", num2str(nDER_Area), ".\n") ); 
    myfprintf(logging, fid, strcat("Number of Batteries in Area ", num2str(Area), " : ", num2str(nBatt_Area), ".\n") ); 
    
    S_onlyDERbuses_Area = S_der_Area(busesWithDERs_Area);   %in PU
    S_onlyBattBusesMax_Area = S_battMax_Area(busesWithBatts_Area);
    
    P_onlyDERbuses_Area = P_der_Area(busesWithDERs_Area);   %in PU
    P_onlyBattBusesMax_Area = P_battMax_Area(busesWithBatts_Area);
    
    E_onlyBattBusesMax_Area = Emax_batt_Area(busesWithBatts_Area);

    lb_Pc_onlyBattBuses_Area = zeros*ones(nBatt_Area, 1);
    ub_Pc_onlyBattBuses_Area = P_onlyBattBusesMax_Area;
    
    lb_Pd_onlyBattBuses_Area = zeros*ones(nBatt_Area, 1);
    ub_Pd_onlyBattBuses_Area = P_onlyBattBusesMax_Area;
    
    lb_B_onlyBattBuses_Area = soc_min.*E_onlyBattBusesMax_Area;
    ub_B_onlyBattBuses_Area = soc_max.*E_onlyBattBusesMax_Area;

    lb_qD_onlyDERbuses_Area = -sqrt( S_onlyDERbuses_Area.^2 - P_onlyDERbuses_Area.^2 );
    ub_qD_onlyDERbuses_Area = sqrt( S_onlyDERbuses_Area.^2 - P_onlyDERbuses_Area.^2 );
    
    lb_qB_onlyBattBuses_Area = -sqrt( S_onlyBattBusesMax_Area.^2 - P_onlyBattBusesMax_Area.^2);
    ub_qB_onlyBattBuses_Area = sqrt( S_onlyBattBusesMax_Area.^2 - P_onlyBattBusesMax_Area.^2);
    
    if t == 1
        myfprintf(logging, fid, "First Time Period, will initialize Battery SOCs for Area %d at the middle of the permissible bandwidth.\n", Area);
        B0Vals_pu_Area = mean([lb_B_onlyBattBuses_Area, ub_B_onlyBattBuses_Area], 2);
    end

    graphDFS_Area = edgeMatrix_Area; %not doing any DFS
    graphDFS_Area_Table = array2table(graphDFS_Area, 'VariableNames', {'fbus', 'tbus'});

    
    R_Area_Matrix = zeros(N_Area, N_Area);
    X_Area_Matrix = zeros(N_Area, N_Area);
    
    % Matrix form of R and X in terms of graph
    for currentBusNum = 1: N_Area - 1
        R_Area_Matrix(fb_Area(currentBusNum), tb_Area(currentBusNum)) = R_Area(currentBusNum);
        R_Area_Matrix(tb_Area(currentBusNum), fb_Area(currentBusNum)) = R_Area_Matrix(fb_Area(currentBusNum), tb_Area(currentBusNum)) ;
        X_Area_Matrix(fb_Area(currentBusNum), tb_Area(currentBusNum)) = X_Area(currentBusNum);
        X_Area_Matrix(tb_Area(currentBusNum), fb_Area(currentBusNum)) = X_Area_Matrix(fb_Area(currentBusNum), tb_Area(currentBusNum)) ;
    end
% Initializing vectors to be used in the Optimization Problem formulation
    
    numVarsFull = [m_Area, m_Area, m_Area, N_Area, nDER_Area, nBatt_Area, nBatt_Area, nBatt_Area, nBatt_Area];
    ranges_Full = generateRangesFromValues(numVarsFull);

    indices_P = ranges_Full{1};
    indices_Q = ranges_Full{2};
    indices_l = ranges_Full{3};
    indices_vAll = ranges_Full{4};
    indices_v = indices_vAll(2:end);
    indices_qD = ranges_Full{5};
    indices_B = ranges_Full{6};
    indices_Pc = ranges_Full{7};
    indices_Pd = ranges_Full{8};
    indices_qB = ranges_Full{9};
    
     myfprintf(logging_Aeq_beq, fid_Aeq_beq, "**********" + ...
        "Constructing Aeq and beq for Area %d.\n" + ...
        "***********\n", Area);

    CVR_P = CVR(1);
    CVR_Q = CVR(2);
    
    % numLinOptEquations = 3*m_Area + 1;
    numLinOptEquationsBFM = 3*m_Area + 1;
    numLinOptEquationsBFM_Batt = numLinOptEquationsBFM + nBatt_Area;
    numLinOptEquations = numLinOptEquationsBFM_Batt;
    % numOptVarsFull = 3*m_Area + N_Area + nDER_Area;
    numOptVarsBFM_Full = 3*m_Area + N_Area;
    numOptVars_BFM_DERs_Full = numOptVarsBFM_Full + nDER_Area;
    numOptVars_BFM_DERs_Batt_Full = numOptVars_BFM_DERs_Full + 4*nBatt_Area;
    numOptVarsFull = numOptVars_BFM_DERs_Batt_Full;
    Aeq_Full = zeros(numLinOptEquations, numOptVarsFull);
    beq_Full = zeros(numLinOptEquations, 1);

    for currentBusNum = 2 : N_Area
        myfprintf(logging_Aeq_beq, fid_Aeq_beq, "*****\n" + ...
            "Checking for bus %d.\n" + ...
            "*****\n", currentBusNum);       
 
        % The row index showing the 'parent' bus of our currentBus:
        
        parentBusIdx = find(tb_Area == currentBusNum);
        parentBusNum = fb_Area(parentBusIdx);
        myfprintf(logging_Aeq_beq, fid_Aeq_beq, "The parent of bus %d is bus %d at index %d.\n", currentBusNum, parentBusNum, parentBusIdx);

        PIdx = parentBusIdx;
        Aeq_Full( PIdx, indices_P(parentBusIdx) ) = 1;
        Aeq_Full( PIdx, indices_l(parentBusIdx) ) = -R_Area_Matrix( parentBusNum, currentBusNum );
        Aeq_Full( PIdx, indices_v(parentBusIdx) ) = -0.5 * CVR_P * lambdaVals(t) * P_L_Area( currentBusNum );

        
        %Q equations
        QIdx = PIdx + m_Area;
        Aeq_Full( QIdx, indices_Q(parentBusIdx) ) = 1;
        Aeq_Full( QIdx, indices_l(parentBusIdx) ) = -X_Area_Matrix( parentBusNum, currentBusNum );
        Aeq_Full( QIdx, indices_v(parentBusIdx) ) = -0.5 * CVR_Q * lambdaVals(t) * Q_L_Area( currentBusNum );

        
       % List of Row Indices showing the set of 'children' buses 'under' our currentBus:
        childBusIndices = find(fb_Area == currentBusNum);
        if ~isempty(childBusIndices)
            Aeq_Full(PIdx, indices_P(childBusIndices) ) = -1;   % for P
            Aeq_Full(QIdx, indices_Q(childBusIndices) ) = -1;   % for Q
        end
        
        myfprintf(logging_Aeq_beq, fid_Aeq_beq, "Aeq(%d, P(%d)) = 1.\n", PIdx, parentBusIdx);
        myfprintf(logging_Aeq_beq, fid_Aeq_beq, "Aeq(%d, l(%d)) = -r(%d, %d).\n", PIdx, parentBusIdx, parentBusNum, currentBusNum);
        for i = 1:length(childBusIndices)
            myfprintf(logging_Aeq_beq, fid_Aeq_beq, "Aeq(%d, P(%d)) = -1\n", PIdx, childBusIndices(i));
        end
        if CVR_P
            myfprintf(logging_Aeq_beq, fid_Aeq_beq, "Aeq(%d, v(%d)) = -0.5 * CVR_P * P_L(%d).\n", PIdx, parentBusIdx, currentBusNum);
        end
        

        myfprintf(logging_Aeq_beq, fid_Aeq_beq, "Aeq(%d, Q(%d)) = 1.\n", QIdx, parentBusIdx);
        myfprintf(logging_Aeq_beq, fid_Aeq_beq, "Aeq(%d, l(%d)) = -x(%d, %d).\n", QIdx, parentBusIdx, parentBusNum, currentBusNum);
        for i = 1:length(childBusIndices)
            myfprintf(logging_Aeq_beq, fid_Aeq_beq, "Aeq(%d, Q(%d)) = -1\n", QIdx, childBusIndices(i));
        end
        if CVR_Q
            myfprintf(logging_Aeq_beq, fid_Aeq_beq, "Aeq(%d, v(%d)) = -0.5 * CVR_Q * Q_L(%d).\n", QIdx, parentBusIdx, currentBusNum);
        end

        % V equations
        vIdx = QIdx + m_Area;
        % Aeq_Full( vIdx, indices_v(parentBusIdx) ) = 1;
        % myfprintf(logging_Aeq_beq, fid_Aeq_beq, "Aeq(%d, v(%d)) = 1\n", vIdx, parentBusIdx);
        Aeq_Full( vIdx, indices_v(parentBusIdx) ) = -1;
        myfprintf(logging_Aeq_beq, fid_Aeq_beq, "Aeq(%d, v(%d)) = -1\n", vIdx, parentBusIdx);
        %Return the rows with the list of 'children' buses of 'under' the PARENT of our currentBus:
        %our currentBus will obviously also be included in the list.
        siblingBusesIndices = find(fb_Area == parentBusNum);
        siblingBuses = tb_Area(siblingBusesIndices);

        myfprintf(logging_Aeq_beq, fid_Aeq_beq, "The siblings of bus %d\n", currentBusNum);
        myfprintf(logging_Aeq_beq, fid_Aeq_beq, "include these buses: %d\n", siblingBuses)
        myfprintf(logging_Aeq_beq, fid_Aeq_beq, "at indices %d.\n", siblingBusesIndices);
        eldestSiblingIdx = siblingBusesIndices(1);
        eldestSiblingBus = siblingBuses(1);
        myfprintf(logging_Aeq_beq, fid_Aeq_beq,  "which makes bus %d at index %d as the eldest sibling.\n", eldestSiblingBus, eldestSiblingIdx);
        % Aeq_Full( vIdx, indices_vAll( eldestSiblingIdx ) ) = -1;
        % myfprintf(logging_Aeq_beq, fid_Aeq_beq, "Aeq(%d, v_Full(%d)) = -1\n", vIdx, eldestSiblingIdx);
        Aeq_Full( vIdx, indices_vAll( eldestSiblingIdx ) ) = 1;
        myfprintf(logging_Aeq_beq, fid_Aeq_beq, "Aeq(%d, v_Full(%d)) = 1\n", vIdx, eldestSiblingIdx);
        % Aeq_Full( vIdx, indices_P(parentBusIdx) ) = 2 * R_Area_Matrix( parentBusNum, currentBusNum );
        Aeq_Full( vIdx, indices_P(parentBusIdx) ) = - 2 * R_Area_Matrix( parentBusNum, currentBusNum );

        % myfprintf(logging_Aeq_beq, fid_Aeq_beq, "Aeq(%d, P(%d)) = 2*r(%d, %d).\n", vIdx, parentBusIdx, parentBusNum, currentBusNum);
        myfprintf(logging_Aeq_beq, fid_Aeq_beq, "Aeq(%d, P(%d)) = -2*r(%d, %d).\n", vIdx, parentBusIdx, parentBusNum, currentBusNum);

        % Aeq_Full( vIdx, indices_Q(parentBusIdx) ) = 2 * X_Area_Matrix( parentBusNum, currentBusNum );
        Aeq_Full( vIdx, indices_Q(parentBusIdx) ) = - 2 * X_Area_Matrix( parentBusNum, currentBusNum );

        % myfprintf(logging_Aeq_beq, fid_Aeq_beq, "Aeq(%d, Q(%d)) = 2*x(%d, %d).\n", vIdx, parentBusIdx, parentBusNum, currentBusNum);
        myfprintf(logging_Aeq_beq, fid_Aeq_beq, "Aeq(%d, Q(%d)) = -2*x(%d, %d).\n", vIdx, parentBusIdx, parentBusNum, currentBusNum);

        % Aeq_Full( vIdx, indices_l(parentBusIdx) ) = ...
        %     -R_Area_Matrix( parentBusNum, currentBusNum )^2 + ...
        %     -X_Area_Matrix( parentBusNum, currentBusNum )^2 ;
        Aeq_Full( vIdx, indices_l(parentBusIdx) ) = ...
            R_Area_Matrix( parentBusNum, currentBusNum )^2 + ...
            +X_Area_Matrix( parentBusNum, currentBusNum )^2 ;
        myfprintf(logging_Aeq_beq, fid_Aeq_beq, "Aeq(%d, l(%d)) = r(%d, %d)^2 + x(%d, %d)^2.\n", vIdx, parentBusIdx, parentBusNum, currentBusNum, parentBusNum, currentBusNum);

        % myfprintf(logging_Aeq_beq, fid_Aeq_beq, "Aeq(%d, l(%d)) = -r(%d, %d)^2 -x(%d, %d)^2.\n", vIdx, parentBusIdx, parentBusNum, currentBusNum, parentBusNum, currentBusNum);
        

        beq_Full(PIdx) = ...
            ( 1- 0.5 * CVR_P ) * ...
            ( lambdaVals(t) * P_L_Area( currentBusNum ) - P_der_Area( currentBusNum )*pvCoeffVals(t) );
        myfprintf(logging_Aeq_beq, fid_Aeq_beq, "beq(%d) = (1 - 0.5*CVR_P)*(P_L(%d) - P_der(%d))\n", PIdx, currentBusNum, currentBusNum);
    
        beq_Full(QIdx) =  ...
            ( 1- 0.5*CVR_Q ) * ...
            ( lambdaVals(t) * Q_L_Area( currentBusNum ) - Q_C_Area( currentBusNum ) );
        myfprintf(logging_Aeq_beq, fid_Aeq_beq, "beq(%d) = (1 - 0.5*CVR_Q)*(Q_L(%d) - Q_C(%d))\n", QIdx, currentBusNum, currentBusNum);

    end
    
    % substation voltage equation
    vSubIdx = 3*m_Area + 1;
    Aeq_Full( vSubIdx, indices_vAll(1) ) = 1;
    myfprintf(logging_Aeq_beq, fid_Aeq_beq, "Aeq(%d, v_Full(1)) = 1\n", vSubIdx);

    beq_Full(vSubIdx) = v_parent_Area;
    myfprintf(logging_Aeq_beq, fid_Aeq_beq, "beq(%d) = %.3f\n", vSubIdx, v_parent_Area);
    
    % DER equation addition
    Table_DER = zeros(nDER_Area, 5);
    
    for i = 1:nDER_Area
        currentBusNum = busesWithDERs_Area(i);
        parentBusIdx = find(tb_Area == currentBusNum);
        QIdx = parentBusIdx + m_Area;
        qD_Idx = indices_qD(i);
        Aeq_Full(QIdx, qD_Idx) = 1;
        myfprintf(logging_Aeq_beq, fid_Aeq_beq, "Aeq(%d, qD(%d)) = 1\n", QIdx, i);
        
        %setting other parameters for DGs:
        Table_DER(i, 2) = qD_Idx;
        
        % slope kq definiton:
        Table_DER(i, 3) = 2*ub_qD_onlyDERbuses_Area(i)/(V_max-V_min); % Qmax at Vmin, and vice versa
        
        % Q_ref, V_ref definition:
        Table_DER(i, 4) = Qref_DER;  %Qref
        Table_DER(i, 5) = Vref_DER;  %Vref
    end
    
    for i = 1:nBatt_Area
        currentBusNum = busesWithBatts_Area(i);
        parentBusIdx = find(tb_Area == currentBusNum);
        PEqnIdx = parentBusIdx;
        QEqnIdx = parentBusIdx + m_Area;
        BEqnIdx = numLinOptEquationsBFM + i;
        
        B_Idx = indices_B(i);
        Pc_Idx = indices_Pc(i);
        Pd_Idx = indices_Pd(i);
        qB_Idx = indices_qB(i);

        Aeq_Full(PEqnIdx, Pc_Idx) = -1;
        myfprintf(logging_Aeq_beq, fid_Aeq_beq, "Aeq(%d, Pc(%d)) = -1\n", PEqnIdx, i);

        Aeq_Full(PEqnIdx, Pd_Idx) = 1;
        myfprintf(logging_Aeq_beq, fid_Aeq_beq, "Aeq(%d, Pd(%d)) = 1\n", PEqnIdx, i);

        Aeq_Full(QEqnIdx, qB_Idx) = 1;
        myfprintf(logging_Aeq_beq, fid_Aeq_beq, "Aeq(%d, qB(%d)) = 1\n", QEqnIdx, i);
        
        % Aeq_Full(BEqnIdx, B_Idx) = 1;
        Aeq_Full(BEqnIdx, B_Idx) = -1;
        % myfprintf(logging_Aeq_beq, fid_Aeq_beq, "Aeq(%d, B(%d)) = 1\n", BEqnIdx, i);
        myfprintf(logging_Aeq_beq, fid_Aeq_beq, "Aeq(%d, B(%d)) = -1\n", BEqnIdx, i);

        % Aeq_Full(BEqnIdx, Pc_Idx) = -delta_t*etta_C;
        Aeq_Full(BEqnIdx, Pc_Idx) = delta_t*etta_C;
        % % myfprintf(logging_Aeq_beq, fid_Aeq_beq, "Aeq(%d, Pc(%d)) = -delta_t*etta_C\n", BEqnIdx, i);
        myfprintf(logging_Aeq_beq, fid_Aeq_beq, "Aeq(%d, Pc(%d)) = delta_t*etta_C\n", BEqnIdx, i);

        % Aeq_Full(BEqnIdx, Pd_Idx) = delta_t/etta_D;
        Aeq_Full(BEqnIdx, Pd_Idx) = -delta_t/etta_D;
        % myfprintf(logging_Aeq_beq, fid_Aeq_beq, "Aeq(%d, Pd(%d)) = delta_t*etta_D\n", BEqnIdx, i);
        myfprintf(logging_Aeq_beq, fid_Aeq_beq, "Aeq(%d, Pd(%d)) = -delta_t*etta_D\n", BEqnIdx, i);


        % beq_Full(BEqnIdx) = B0Vals_pu_Area(i);
        beq_Full(BEqnIdx) = -B0Vals_pu_Area(i);
        % myfprintf(logging_Aeq_beq, fid_Aeq_beq, "beq(%d) = B0(%d) = %f\n", BEqnIdx, i, B0Vals_pu_Area(i));
        myfprintf(logging_Aeq_beq, fid_Aeq_beq, "beq(%d) = B0(%d) = %f\n", BEqnIdx, i, beq_Full(BEqnIdx));

    end

    if fileOpenedFlag_Aeq_beq
        fclose(fid_Aeq_beq);
    end

    % plotSparsity(Aeq_Full, beq_Full);
    ext = ".csv";
    saveLocationFolderName = strcat("processedData", filesep , systemName, filesep, "numAreas_", num2str(numAreas), filesep, "Area", num2str(Area));
    if ~exist("saveLocationFolderName", 'dir')
        mkdir(saveLocationFolderName)
    end
    filenameAeq = strcat(saveLocationFolderName, filesep, "Aeq_A_T_", num2str(T), "_macroItr_", num2str(macroItr), ext);
    % Saving Aeq to a CSV file
    writematrix(Aeq_Full, filenameAeq);
    filenamebeq = strcat(saveLocationFolderName, filesep, "beq_A_T_", num2str(T), "_macroItr_", num2str(macroItr), ext);

    % Saving beq to a CSV file
    writematrix(beq_Full, filenamebeq);


    x_NoLoss = singlephaselin(busDataTable_pu_Area, branchDataTable_Area, v_parent_Area, S_connection_Area, B0Vals_pu_Area, isLeaf_Area, ...
        Area, numAreas, graphDFS_Area_Table, R_Area_Matrix, X_Area_Matrix, t, macroItr, lambdaVals, pvCoeffVals, 'verbose', false, 'logging', false);


    numVarsNoLoss = [m_Area, m_Area, N_Area, nDER_Area, nBatt_Area, nBatt_Area, nBatt_Area, nBatt_Area];
    ranges_noLoss = generateRangesFromValues(numVarsNoLoss);

    indices_P_noLoss = ranges_noLoss{1};
    indices_Q_noLoss = ranges_noLoss{2};
    indices_vFull_noLoss = ranges_noLoss{3};
    indices_qD_noLoss = ranges_noLoss{4};
    indices_B_noLoss = ranges_noLoss{5};
    indices_Pc_noLoss = ranges_noLoss{6};
    indices_Pd_noLoss = ranges_noLoss{7};
    indices_qB_noLoss = ranges_noLoss{8};
    
    P0_NoLoss = x_NoLoss( indices_P_noLoss );
    Q0_NoLoss = x_NoLoss( indices_Q_noLoss );
    v0_NoLoss =  x_NoLoss( indices_vFull_noLoss );
    qD0_NoLoss = x_NoLoss( indices_qD_noLoss );
    B0_NoLoss = x_NoLoss(indices_B_noLoss);
    Pc0_NoLoss = x_NoLoss(indices_Pc_noLoss);
    Pd0_NoLoss = x_NoLoss(indices_Pd_noLoss);
    qB0_NoLoss = x_NoLoss(indices_qB_noLoss);
    
    l0_NoLoss = zeros(m_Area, 1);

    for currentBusNum = 2 : N_Area
        parentBusIdx = find(tb_Area == currentBusNum);
        siblingBusesIndices = find(parentBusNum == fb_Area);
        l0_NoLoss( parentBusIdx ) = ( P0_NoLoss(parentBusIdx)^2 + Q0_NoLoss(parentBusIdx)^2 ) / v0_NoLoss(siblingBusesIndices(1));
    end
    
    x0 = [P0_NoLoss; Q0_NoLoss; l0_NoLoss; v0_NoLoss; qD0_NoLoss; B0_NoLoss; Pc0_NoLoss; Pd0_NoLoss; qB0_NoLoss];
    
    numVarsForBoundsFull = [1, numVarsFull(1) - 1, numVarsFull(2:4) ]; % qD limits are specific to each machine, will be appended later.
    lbVals = [0, -5, -15, 0, V_min^2];
    ubVals = [5, 5, 5, 15, V_max^2];
    [lb_Area, ub_Area] = constructBoundVectors(numVarsForBoundsFull, lbVals, ubVals);
    lb_AreaFull = [lb_Area; lb_qD_onlyDERbuses_Area; lb_B_onlyBattBuses_Area; lb_Pc_onlyBattBuses_Area; lb_Pd_onlyBattBuses_Area; lb_qB_onlyBattBuses_Area];
    ub_AreaFull = [ub_Area; ub_qD_onlyDERbuses_Area; ub_B_onlyBattBuses_Area; ub_Pc_onlyBattBuses_Area; ub_Pd_onlyBattBuses_Area; ub_qB_onlyBattBuses_Area];
    
    % displayIterations = "iter-detailed";
    displayIterations = "off";
    options = optimoptions('fmincon', 'Display', displayIterations, 'MaxFunctionEvaluations', 100000000, 'Algorithm', 'sqp');
    
    t3Start = tic;
    
    flaggedForLimitViolation = false;

    for varNum = 1:numOptVarsFull
        lbVal = lb_AreaFull(varNum);
        ubVal = ub_AreaFull(varNum);
        x0Val = x0(varNum);
        if lbVal > x0Val
            myfprintf(logging, fid, "Time Period = %d, macroItr = %d and Area = %d: Oh no! x0(%d) < lb(%d) as %f < %f.\n", t, macroItr, Area, varNum, varNum, x0Val, lbVal);
            flaggedForLimitViolation = true;
        end
        if ubVal < x0Val
            myfprintf(logging, fid, "Time Period = %d, macroItr = %d and Area = %d: Oh no! x0_NoLoss(%d) > ub(%d) as %f > %f.\n", t, macroItr, Area, varNum, varNum, x0Val, ubVal);
            flaggedForLimitViolation = true;
        end
    end
    
    if checkOptimalSolutionWithinBounds(x0, lb_AreaFull, ub_AreaFull)
        myfprintf(logging, fid, "Time Period = %d, macroItr = %d and Area = %d:  My native bound checker says that bounds are Actually being violated.\n", t, macroItr, Area);
        error("Nani?");
    elseif flaggedForLimitViolation
        myfprintf(logging, fid, "Time Period = %d, macroItr = %d and Area = %d:  x0 within limits anyway? More like MATLAB stupid? Initialization successful. Proceeding to solving for full optimization problem.\n", t, macroItr, Area)
    else
        myfprintf(logging, fid, "Time Period = %d, macroItr = %d and Area = %d:  x0 within limits. Initialization successful. Proceeding to solving for the full optimization problem.\n", t, macroItr, Area);
    end

    myfprintf(logging, fid, "Time Period = %d, macroItr = %d and Area = %d:  Now solving for the real deal.\n", t, macroItr, Area);

    [x, fval, ~, ~] = fmincon( @(x)objfun(x, N_Area, nDER_Area, nBatt_Area, fb_Area, tb_Area, R_Area_Matrix, X_Area_Matrix, 'mainObjFun', "func_PLoss", 'secondObjFun', "func_SCD"), ...
                              x0, [], [], Aeq_Full, beq_Full, lb_AreaFull, ub_AreaFull, ...
                              @(x)eqcons(x, Area, N_Area, ...
                              fb_Area, tb_Area, indices_P, indices_Q, indices_l, indices_vAll, ...
                              macroItr, systemName, numAreas, "verbose", false, "saveToFile", false),...
                              options);
    
    % macroIterationPLoss = fval;
    macroIterationQLoss = objfun(x, N_Area, nDER_Area, nBatt_Area, fb_Area, tb_Area, R_Area_Matrix, X_Area_Matrix, 'mainObjFun', "func_QLoss", 'secondObjFun', "none");

    t3 = toc(t3Start);
    
    time_dist(macroItr, Area) = t3;
    
    % Result
    P_Area = x(indices_P); %m_Areax1
    Q_Area = x(indices_Q); %m_Areax1
    % S_Area = complex(P_Area, Q_Area); %m_Areax1
    % l_Area = x(indices_l);
    % v_Area = x(indices_vAll); %N_Areax1
    qD_Area = x(indices_qD);
    % v_Area(1) = v_parent_Area;
    B_Area = x(indices_B);
    Pd_Area = x(indices_Pd);
    Pc_Area = x(indices_Pc);
    qB_Area = x(indices_qB);

    qD_AllBuses = zeros(N_Area, 1);

    for i = 1 : nDER_Area
        busNum = busesWithDERs_Area(i);
        qD_AllBuses(busNum) = qD_Area(i);
    end
    
    [B_AllBuses, Pd_AllBuses, Pc_AllBuses, qB_AllBuses] = deal(zeros(N_Area, 1));

    for i = 1 : nBatt_Area
        busNum = busesWithBatts_Area(i); 
        B_AllBuses(busNum) = B_Area(i);
        Pc_AllBuses(busNum) = Pc_Area(i);
        Pd_AllBuses(busNum) = Pd_Area(i);
        qB_AllBuses(busNum) = qB_Area(i);
    end
    
    P_inFlowArea = P_Area(1);
    P_der_Total = sum(P_der_Area)*pvCoeffVals(t);
    Pd_Total = sum(Pd_Area);
    Pc_Total = sum(Pc_Area);
    PLoad_Total = lambdaVals(t) * sum(P_L_Area);

    PLoss = P_inFlowArea + P_der_Total + Pd_Total - PLoad_Total - Pc_Total;
    percentageSavings = 100* (Pd_Total - Pc_Total) / (P_inFlowArea + P_der_Total + Pd_Total - Pc_Total);
    
    Q_inFlowArea = Q_Area(1);
    qD_Total = sum(qD_Area);
    qB_Total = sum(qB_Area);
    QLoad_Total = lambdaVals(t) * sum(Q_L_Area);

    QLoss = Q_inFlowArea + qD_Total + qB_Total - QLoad_Total;

    myfprintf(logging, fid, "Time Period = %d, macroItr = %d and Area = %d: " + ...
        "Projected savings in substation power flow by using batteries: " + ...
        "%f percent.\n", t, macroItr, Area, percentageSavings); % always true

    macroIterationPLosses(macroItr, Area) = PLoss;
    macroIterationQLosses(macroItr, Area) = macroIterationQLoss;
    % macroIterationQLosses(macroItr, Area) = QLoss;
    macroIterationPSaves(macroItr, Area) = percentageSavings;

    %  if fileOpenedFlag
    %     fclose(fid);
    % end

end